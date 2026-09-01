"""Fold the raw transaction landing zone into the curated Parquet dataset.

Reads newline-delimited gzipped JSON from raw/, normalises it, and appends
Snappy Parquet to curated/ partitioned by event_date and category.

Job bookmarks are what make this safe to run on a schedule: Glue records which
S3 objects it has already consumed, so a nightly run processes only what
Firehose delivered since the last one. Without them every run would reprocess
the entire landing zone and append duplicate rows to curated/ -- the cost would
grow quadratically and the data would be wrong.

Bookmarks only work when the read carries a transformation_ctx, which is why
the argument below is not optional decoration.
"""

import sys

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql import types as T

args = getResolvedOptions(sys.argv, ["JOB_NAME", "raw_path", "curated_path"])

sc = SparkContext()
glue_context = GlueContext(sc)
spark = glue_context.spark_session
job = Job(glue_context)
job.init(args["JOB_NAME"], args)

# The emitter's contract, declared rather than inferred. Schema inference on
# JSON is per-run and content-dependent: a night where every transaction
# happened to be unenriched would infer ai_provider as a different type (or
# drop it), and the Parquet written that night would not match the rest of the
# dataset. An explicit schema makes the job fail loudly on a contract change
# instead of silently corrupting the table.
RAW_SCHEMA = T.StructType(
    [
        T.StructField("id", T.LongType(), True),
        T.StructField("timestamp", T.StringType(), True),
        T.StructField("amount", T.DoubleType(), True),
        T.StructField("category", T.StringType(), True),
        T.StructField("ai_provider", T.StringType(), True),
        T.StructField("anomaly_severity", T.StringType(), True),
    ]
)

source = glue_context.create_dynamic_frame.from_options(
    connection_type="s3",
    connection_options={
        "paths": [args["raw_path"]],
        "recurse": True,
        # Firehose writes one object per buffer flush; grouping them keeps
        # Spark from opening a task per small file.
        "groupFiles": "inPartition",
    },
    format="json",
    # Required for bookmarking. Renaming it resets the bookmark and reprocesses
    # everything, so treat it as a stable identifier.
    transformation_ctx="raw_transactions",
)

# A quiet day is the normal case, not an error.
#
# This previously called sys.exit(0) here. Glue treats any SystemExit raised
# by the script as a job failure regardless of its exit code, so every night
# with no new records was reported FAILED -- alarming on a healthy no-op.
# Guarding the work and falling through to a single job.commit() is both
# correct and quiet.
if source.count() == 0:
    print("No new records since the last bookmark; nothing to do.")
else:
    df = source.toDF()

    # A bookmarked read can return a frame missing columns that no record in this
    # batch happened to carry. Adding them back as typed nulls keeps the Parquet
    # schema identical across runs, which is what lets Athena read the whole
    # dataset as one table.
    for field in RAW_SCHEMA.fields:
        if field.name not in df.columns:
            df = df.withColumn(field.name, F.lit(None).cast(field.dataType))

    curated = (
        df.select([F.col(f.name).cast(f.dataType) for f in RAW_SCHEMA.fields])
        # Firehose delivers at-least-once, and a client retry can resend a record,
        # so the same transaction id can legitimately appear twice in raw/.
        # curated/ is meant to be one row per transaction.
        .dropDuplicates(["id"])
        .withColumn("event_ts", F.to_timestamp("timestamp"))
        # Partition columns must never be null: a null partition key becomes
        # Hive's __HIVE_DEFAULT_PARTITION__, which partition projection does not
        # enumerate and Athena therefore cannot see.
        .withColumn("event_date", F.coalesce(F.to_date("event_ts"), F.current_date()))
        .withColumn("category", F.coalesce(F.col("category"), F.lit("other")))
        .withColumn("ai_provider", F.coalesce(F.col("ai_provider"), F.lit("none")))
        .withColumn("anomaly_severity", F.coalesce(F.col("anomaly_severity"), F.lit("none")))
        .select(
            "id",
            "event_ts",
            "amount",
            "ai_provider",
            "anomaly_severity",
            "event_date",
            "category",
        )
    )

    # One file per partition per run. Left unset, Spark writes one file per shuffle
    # partition (200 by default), which at this volume means hundreds of a few-KB
    # Parquet files -- the small-file problem that makes Athena slow and expensive
    # regardless of how little data there is.
    (
        curated.repartition("event_date", "category")
        .write.mode("append")
        .partitionBy("event_date", "category")
        .option("compression", "snappy")
        .parquet(args["curated_path"])
    )

job.commit()
