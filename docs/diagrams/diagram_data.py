import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from awsdiag import *

W, H = 1660, 780
c = Canvas(W, H)

c.frame(36, 44, 1588, 620, "AWS Cloud", INK, icon="general/general.png")

# ---- producer, in the compute stack ---------------------------------------
c.frame(70, 92, 250, 200, "Compute stack", ORANGE, fill="#FFF6EE", opacity=0.7, dashed=True)
c.node(195, 178, "compute/fargate.png", "ECS Fargate task",
       ["writes to RDS first,", "then emits asynchronously,", "bounded, drops on", "backpressure"])

# ---- the data stack -------------------------------------------------------
DX, DY, DW, DH = 360, 92, 1230, 500
c.frame(DX, DY, DW, DH, "Data stack &#183; separate root module, separate state, no remote-state link",
        TEAL, fill="#F2FAFA", opacity=0.5)

IY = 190
c.node(470,  IY, "analytics/kinesis-data-firehose.png", "Kinesis Firehose",
       ["Direct PUT &#183; no idle cost", "gzip NDJSON", "buffer 128 MB / 300 s"])
c.node(760,  IY, "storage/simple-storage-service-s3.png", "S3 data lake",
       ["raw/yyyy/MM/dd/", "expires at 30 days"])
c.node(1060, IY, "analytics/glue.png", "Glue PySpark ETL",
       ["2 &#215; G.1X &#183; 15 min cap", "bookmarks &#183; dedupe by id"], above=True)
c.node(1370, IY, "storage/simple-storage-service-s3.png", "S3 curated",
       ["Snappy Parquet", "event_date / category", "&#8594; Standard-IA at 90d"])

QY = 462
c.node(760,  QY, "integration/eventbridge-scheduler.png", "EventBridge Scheduler",
       "starts the Glue job")
c.node(1100, QY, "analytics/glue-data-catalog.png", "Glue Data Catalog",
       ["table definition,", "partition projection"])
c.node(1400, QY, "analytics/athena.png", "Athena",
       ["workgroup &#183; 1 GiB scan cap", "results expire at 30d"])

c.link([(238, IY), (444, IY)], "PutRecordBatch", ly=IY-10)
c.link([(496, IY), (734, IY)])
c.link([(786, IY), (1034, IY)])
c.link([(1086, IY), (1344, IY)])

# The schedule targets the Glue job, not the bucket.
c.link([(760, QY-26), (760, 344), (1060, 344), (1060, IY+30)],
       "nightly 03:00 UTC", lx=910, ly=338)
# Athena reads data from the curated prefix and its table shape from the catalog.
c.link([(1370, 290), (1370, 392), (1400, 392), (1400, QY-26)], dashed=True, color=GREY)
c.text(1430, 372, "Parquet, partition-pruned", 10.5, "400", GREY)
c.link([(1123, QY), (1377, QY)], dashed=True, color=GREY)

c.frame(410, 300, 300, 116, "Not emitted", "#B0084D", fill="#FFF1F5", opacity=0.7)
c.text(430, 340, "description &#183; account id &#183; user id", 11, "400", GREY)
c.text(430, 358, "anomaly reason", 11, "400", GREY)
c.text(430, 384, "six fields only, asserted by a test", 10.5, "600", "#B0084D")

c.text(830, 700, "Off by default. With DATA_PIPELINE=off the application builds a no-op emitter, "
                 "makes no AWS calls and costs nothing.", 11.5, "400", GREY, "middle", italic=True)
c.text(830, 722, "Destroying the compute stack leaves everything here untouched, and Athena keeps "
                 "answering while the application is down.", 11.5, "400", GREY, "middle", italic=True)

print(c.render(sys.argv[1]))
