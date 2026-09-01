import os, sys; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from awsdiag import *

W, H = 1660, 1250
c = Canvas(W, H)

c.node(148, 60, "general/user.png", "User", size=38)

c.frame(36, 118, 1588, 1094, "AWS Cloud", INK, icon="general/general.png")

# ---- top band -------------------------------------------------------------
BY, ICY = 158, 232
c.frame(70,   BY, 560, 178, "Edge",               GRAY, fill="#F7F8FA", opacity=0.6)
c.frame(660,  BY, 180, 178, "Identity",           GRAY, fill="#F7F8FA", opacity=0.6)
c.frame(870,  BY, 180, 178, "AI",                 GRAY, fill="#F7F8FA", opacity=0.6)
c.frame(1080, BY, 470, 178, "Images and secrets", GRAY, fill="#F7F8FA", opacity=0.6)

c.node(148,  ICY, "network/route-53.png",                  "Route 53",    "DNS, alias to CF")
c.node(300,  ICY, "network/cloudfront.png",                "CloudFront",  "TLS, two origins")
c.node(452,  ICY, "storage/simple-storage-service-s3.png", "S3",          "React bundle")
c.node(580,  ICY, "security/waf.png",                      "WAF",         "web ACL")
c.node(750,  ICY, "security/cognito.png",                  "Cognito",     ["user pool,", "hosted UI + PKCE"])
c.node(960,  ICY, "ml/bedrock.png",                        "Bedrock",     ["Claude: categorize,", "flag, summarize"])
c.node(1160, ICY, "compute/ec2-container-registry.png",    "ECR",         "app image")
c.node(1315, ICY, "security/secrets-manager.png",          "Secrets Mgr", "RDS credentials")
c.node(1470, ICY, "security/key-management-service.png",   "KMS",         "CMK, at rest")

# ---- VPC ------------------------------------------------------------------
VX, VY, VW, VH = 70, 396, 1480, 610
c.frame(VX, VY, VW, VH, "VPC &#183; us-east-2 &#183; 10.0.0.0/16", GREEN, icon="network/vpc.png")

MID = VX + VW / 2
PUB_Y, APP_Y, DAT_Y = VY + 60, VY + 226, VY + 424
# Broken around the ALB, which is one regional resource spanning both zones.
for y0, y1 in [(VY+52, 495), (600, VY+VH-14)]:
    c.bg.append(f'<path d="M {MID} {y0} L {MID} {y1}" stroke="{TEAL}" stroke-width="1.5" '
                f'stroke-dasharray="7 5" fill="none"/>')
c.text(VX + VW*0.25, VY + 46, "Availability Zone A", 12, "600", TEAL, "middle")
c.text(VX + VW*0.75, VY + 46, "Availability Zone B", 12, "600", TEAL, "middle")

c.band(VX+22, PUB_Y, VW-44, 150, "Public subnets",      GREEN, GREEN)
c.band(VX+22, APP_Y, VW-44, 178, "Private app subnets", TEAL,  TEAL)
c.band(VX+22, DAT_Y, VW-44, 150, "Private data subnets", BLUE, BLUE)
c.text(VX+VW-36, DAT_Y+25, "no route to the internet", 11, "400", BLUE, "end")

c.node(200,  PUB_Y+82, "network/internet-gateway.png", "Internet gateway")
c.node(430,  PUB_Y+82, "network/nat-gateway.png",      "NAT gateway", "one by default, AZ A")
c.node(MID,  PUB_Y+82, "network/elb-application-load-balancer.png",
       "Application Load Balancer", "one, spanning both zones", above=True)

c.node(380,  APP_Y+86, "compute/fargate.png", "ECS Fargate task", ["desired_count = 2", "no EC2, no autoscaling"])
c.node(1120, APP_Y+86, "compute/fargate.png", "ECS Fargate task", ["256 CPU / 512 MB", "port 3000"])

EX, EY, EW = 1250, APP_Y+34, 280
c.frame(EX, EY, EW, 122, "VPC endpoints", TEAL, fill="#FFFFFF", dashed=True)
c.text(EX+EW/2, EY+52, "ecr.api &#183; ecr.dkr &#183; logs", 11, "400", GRAY, "middle")
c.text(EX+EW/2, EY+69, "secretsmanager &#183; S3 gateway", 11, "400", GRAY, "middle")
c.text(EX+EW/2, EY+94, "optional &#183; off by default", 10, "400", ORANGE, "middle")

c.node(380,  DAT_Y+80, "database/rds-postgresql-instance.png", "RDS PostgreSQL 16", "primary")
c.node(1120, DAT_Y+80, "database/rds-postgresql-instance.png", "RDS standby", "Multi-AZ")

# ---- observability --------------------------------------------------------
OY = 1032
c.frame(70, OY, 1480, 150, "Observability and audit", GRAY, fill="#F7F8FA", opacity=0.6)
for cx, ic, lb, sb in [
    (245,  "management/cloudwatch.png",                       "CloudWatch", "logs + 5 alarms"),
    (540,  "integration/simple-notification-service-sns.png", "SNS",        "alert topic"),
    (835,  "management/cloudtrail.png",                       "CloudTrail", "API audit log"),
    (1130, "security/guardduty.png",                          "GuardDuty",  "findings to SNS"),
    (1420, "management/config.png",                           "Config",     "resource history"),
]:
    c.node(cx, OY+78, ic, lb, sb)

# ---- request path ---------------------------------------------------------
c.link([(148, 102), (148, ICY-26)])
c.link([(178, ICY), (274, ICY)])
c.link([(326, ICY), (426, ICY)], "static", ly=ICY-8)
c.link([(300, 300), (300, 500), (MID, 500), (MID, PUB_Y+56)], "/api/*", lx=560, ly=494)
c.link([(MID-22, PUB_Y+108), (MID-22, APP_Y+44), (380, APP_Y+44), (380, APP_Y+60)])
c.link([(MID+22, PUB_Y+108), (MID+22, APP_Y+44), (1120, APP_Y+44), (1120, APP_Y+60)])
c.link([(380,  APP_Y+156), (380,  DAT_Y+54)], "TLS", ly=812)
c.link([(1120, APP_Y+156), (1120, DAT_Y+54)], "TLS", ly=812)
c.link([(420, DAT_Y+80), (1080, DAT_Y+80)], "synchronous replication",
       dashed=True, color=BLUE, ly=DAT_Y+74)

# ---- dependencies ---------------------------------------------------------
c.link([(167, 60), (750, 60), (750, ICY-26)], "1. sign in &#183; authorization code + PKCE",
       dashed=True, color=GRAY, lx=430, ly=54)
c.link([(750, 306), (750, 370), (250, 370), (250, APP_Y+86), (354, APP_Y+86)],
       "2. JWKS &#183; RS256, token_use, client_id", dashed=True, color=GRAY, lx=500, ly=364)
c.link([(960, 322), (960, 700), (1071, 700)], "task role", dashed=True, color=GRAY,
       lx=960, ly=366)
c.link([(1160, 296), (1160, 600), (1290, 600), (1290, EY-6)], "image pull",
       dashed=True, color=GRAY, lx=1160, ly=366)
c.link([(1315, 296), (1315, EY-6)], "credentials", dashed=True, color=GRAY, lx=1315, ly=366)
c.link([(EX, EY+61), (1150, EY+61)], "private path", dashed=True, color=GRAY,
       lx=1198, ly=EY+55)
c.link([(405, APP_Y+70), (430, APP_Y+70), (430, PUB_Y+110)], "egress only",
       dashed=True, color=GRAY, lx=478, ly=APP_Y+30)
c.link([(407, PUB_Y+82), (223, PUB_Y+82)], dashed=True, color=GRAY)
c.link([(580, ICY-26), (580, 142), (300, 142), (300, ICY-26)], "inspects",
       dashed=True, color=GRAY, lx=440, ly=136)

c.text(830, 1234, "Defaults shown. WAF, GuardDuty, RDS Multi-AZ and the VPC endpoints are "
                  "variables; the sandbox this was deployed into forbids several of them.",
       11, "400", GRAY, "middle", italic=True)

print(c.render(sys.argv[1]))
