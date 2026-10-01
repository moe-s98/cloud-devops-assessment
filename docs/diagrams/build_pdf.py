"""Build docs/Architecture-Diagrams.pdf from the rendered diagram PNGs.

Run:  docker run --rm -v "$PWD":/w -w /w python:3.12-slim \
        sh -c "pip install -q reportlab pillow && python docs/diagrams/build_pdf.py"
"""

from pathlib import Path

from PIL import Image
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.platypus import (
    Image as RLImage,
)
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)

ROOT = Path(__file__).resolve().parent
RENDERED = ROOT / "rendered"
OUT = ROOT.parent / "Architecture-Diagrams.pdf"

PAGE = landscape(A4)
MARGIN = 12 * mm
ORANGE = colors.HexColor("#FF9900")
NAVY = colors.HexColor("#232F3E")
GREY = colors.HexColor("#5B6475")

DIAGRAMS = [
    ("01-aws-architecture", "Full AWS architecture",
     "Every component of the dev environment and how they connect. Users only reach CloudFront: "
     "<b>/*</b> is served from a private S3 bucket through Origin Access Control, and <b>/api/*</b> goes through a "
     "CloudFront <b>VPC origin</b> to an <b>internal</b> ALB, so nothing in the VPC is reachable from the internet. "
     "Fargate tasks talk to RDS over TLS, pull images from ECR, get the DB password from Secrets Manager at start-up "
     "and ship JSON logs to CloudWatch. Alarms and backup failures go to an encrypted SNS topic. GitLab CI builds "
     "the image, pushes it to ECR and Docker Hub, and applies Terraform with state in a locked S3 bucket."),
    ("02-network", "Network: subnets, routing and gateways",
     "VPC 10.20.0.0/16 across two AZs with three subnet tiers per AZ (/20 each). <b>Public</b> subnets route "
     "0.0.0.0/0 to the internet gateway. <b>Private</b> subnets hold the internal ALB, with one route table per AZ so "
     "prod NAT traffic stays in-zone. <b>Data</b> subnets have only the local route, so the database has no path "
     "to the internet at all. A free S3 gateway endpoint keeps ECR image layers on the AWS network, VPC flow logs "
     "record rejected traffic, and the default security group is stripped of all rules."),
    ("03-security-groups", "Security-group chain (least-privilege ports)",
     "Each tier accepts traffic only from the tier in front of it, referenced by <b>security-group ID</b>, never "
     "by CIDR. The ALB accepts port 80 only from CloudFront's managed origin-facing prefix list. App tasks accept "
     "8000 only from the ALB SG. The database accepts 5432 only from the app SG and has <b>no egress</b>. "
     "Anything else is dropped, and the ALB has no public IP to begin with."),
    ("04-iam-secrets", "IAM and secrets: who can do what",
     "<b>CI:</b> two IAM users whose only permission is <b>sts:AssumeRole</b> on one role each (1-hour sessions). "
     "The deploy key is a <b>protected</b> GitLab variable, so only pipelines on main can use it. The deploy role "
     "is scoped by service, region and name prefix, with an explicit deny on editing CI identities. "
     "<b>Runtime:</b> the ECS execution role can read exactly one secret and decrypt with one key. The task role "
     "has <b>no permissions</b>. The DB password is generated and rotated by RDS and injected at container start, "
     "so it's never in code, CI, logs or Terraform state."),
    ("05-request-flow", "Request lifecycle",
     "What happens when a user loads the page and posts a message: HTTP→HTTPS redirect, edge caching, the "
     "SigV4-signed S3 read via OAC, the <b>X-Origin-Verify</b> header check on the ALB (default action 403), "
     "pydantic input validation, a parameterized INSERT over TLS, and security headers on every response."),
    ("06-terraform-modules", "Terraform structure and module dependencies",
     "<b>bootstrap</b> is applied once: the state bucket, the shared ECR repository and the CI identities. "
     "<b>stack</b> is the single composition root that wires 8 reusable modules together. <b>envs/dev</b> and "
     "<b>envs/prod</b> contain only values (tfvars and a backend key), so the two environments can't drift in "
     "code. Arrows show which outputs feed which module."),
    ("07-cicd-pipeline", "CI/CD pipeline: 10 stages, 16 jobs",
     "lint (ruff, hadolint, fmt/validate, tflint, Checkov, gitleaks) → test (pytest + SonarQube quality gate) "
     "→ build the image <b>once</b> → Trivy gate on fixable HIGH/CRITICAL <b>before</b> any push → publish to "
     "ECR and Docker Hub → plan with a <b>read-only</b> role → apply the saved plan to dev → smoke test → "
     "automatic rollback on failure → <b>manual</b> promotion of the same image to prod."),
    ("08-deploy-rollback", "Zero-downtime deploy and the two rollback layers",
     "ECS rolling update with 100 % minimum healthy: the old task keeps serving until the new one passes health "
     "checks. If the new version <b>crashes</b>, the ECS deployment circuit breaker rolls back by itself. If it "
     "<b>runs but behaves wrong</b>, the smoke test fails and the rollback job restores the task definition "
     "recorded just before the deploy."),
    ("09-monitoring", "Monitoring, logging and alerting",
     "Sources: structured JSON app logs, ALB, ECS and RDS metrics, RDS logs, VPC flow logs and AWS Backup events. "
     "A metric filter turns ERROR log lines into a metric. There are 8 CloudWatch alarms plus an EventBridge rule "
     "for backup failures, all going to an encrypted SNS topic and email. A dashboard defined in Terraform shows "
     "traffic, errors, latency, saturation and recent errors. The same metrics drive target-tracking autoscaling."),
    ("10-backup-dr", "Backups and disaster recovery (four layers)",
     "1) RDS automated backups with point-in-time recovery. 2) An AWS Backup plan (daily, weekly in prod) into a "
     "vault with its <b>own</b> KMS key, selected by tag. 3) In prod, a cross-region copy and a <b>vault lock</b> in "
     "compliance mode (ransomware protection). 4) S3 versioning on the frontend and state buckets. Failed or "
     "aborted backup jobs raise an email alert."),
    ("11-restore-drill", "Restore drill: proving backups actually work",
     "scripts/restore-drill.sh writes marker A, records time T, writes marker B, restores the database "
     "<b>to time T as a new instance</b>, then queries the copy from inside the VPC with a one-off ECS task. "
     "PASS means A is present and B is absent, so the restore landed on the exact second requested. It reports the "
     "measured RTO and always deletes the copy."),
    ("12-dev-vs-prod", "dev vs prod: same code, different values",
     "dev (deployed, about $1.70/day): 2 AZs, no NAT, 1–3 small tasks, single-AZ micro database, no WAF. "
     "prod (defined as code, manual promotion, about $8–10/day): 3 AZs, NAT per AZ with private tasks, 2–10 "
     "larger tasks, Multi-AZ database with deletion protection, WAF, 14/90-day backups, cross-region copy and "
     "vault lock."),
]

title_style = ParagraphStyle("t", fontName="Helvetica-Bold", fontSize=17, textColor=NAVY, leading=21)
num_style = ParagraphStyle("n", fontName="Helvetica-Bold", fontSize=10, textColor=ORANGE, leading=12)
body_style = ParagraphStyle("b", fontName="Helvetica", fontSize=9.2, textColor=GREY, leading=12.5)


def footer(canvas, doc):
    canvas.saveState()
    w, _ = PAGE
    canvas.setStrokeColor(ORANGE)
    canvas.setLineWidth(1.2)
    canvas.line(MARGIN, 9 * mm, w - MARGIN, 9 * mm)
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(GREY)
    canvas.drawString(MARGIN, 5 * mm, "Guestbook on AWS · Architecture diagrams · Mohamed Samir")
    canvas.drawRightString(w - MARGIN, 5 * mm, f"Page {doc.page}")
    canvas.restoreState()


def fitted_image(path: Path, max_w: float, max_h: float) -> RLImage:
    with Image.open(path) as im:
        w, h = im.size
    scale = min(max_w / w, max_h / h)
    return RLImage(str(path), width=w * scale, height=h * scale)


def cover() -> list:
    big = ParagraphStyle("c", fontName="Helvetica-Bold", fontSize=34, textColor=NAVY, leading=40)
    sub = ParagraphStyle("s", fontName="Helvetica", fontSize=14, textColor=GREY, leading=19)
    small = ParagraphStyle("sm", fontName="Helvetica", fontSize=10, textColor=GREY, leading=14)
    story = [
        Spacer(1, 18 * mm),
        Paragraph("Guestbook on AWS", big),
        Spacer(1, 4 * mm),
        Paragraph("Architecture diagrams: Cloud / DevOps Engineer take-home assessment", sub),
        Spacer(1, 8 * mm),
    ]
    facts = [
        ["Cloud", "AWS eu-north-1 (Stockholm), Free plan account"],
        ["IaC", "Terraform 1.16: bootstrap + 8 modules + one composition root, dev/prod tfvars"],
        ["Compute / data", "ECS Fargate behind an internal ALB · RDS PostgreSQL 16 · AWS Backup"],
        ["Edge", "CloudFront: S3 via OAC for /*, VPC origin to the internal ALB for /api/*"],
        ["CI/CD", "GitLab CI: lint · test · SonarQube · build · Trivy · publish · plan · deploy · smoke · rollback · promote"],
        ["Security", "SG chain, isolated data subnets, KMS everywhere, TLS to DB, assume-role CI, zero public ingress into the VPC"],
    ]
    t = Table(facts, colWidths=[38 * mm, 200 * mm])
    t.setStyle(TableStyle([
        ("FONT", (0, 0), (0, -1), "Helvetica-Bold", 10),
        ("FONT", (1, 0), (1, -1), "Helvetica", 10),
        ("TEXTCOLOR", (0, 0), (0, -1), NAVY),
        ("TEXTCOLOR", (1, 0), (1, -1), GREY),
        ("LINEBELOW", (0, 0), (-1, -1), 0.4, colors.HexColor("#E5E7EB")),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    story += [t, Spacer(1, 8 * mm), Paragraph("<b>Contents</b>", ParagraphStyle(
        "h", fontName="Helvetica-Bold", fontSize=12, textColor=NAVY, leading=16))]
    rows = [[f"{i:02d}", name, f"page {i + 1}"] for i, (_, name, _) in enumerate(DIAGRAMS, start=1)]
    half = (len(rows) + 1) // 2
    toc = Table(
        [rows[i] + ([""] + rows[i + half] if i + half < len(rows) else ["", "", "", ""]) for i in range(half)],
        colWidths=[10 * mm, 88 * mm, 20 * mm, 8 * mm, 10 * mm, 88 * mm, 20 * mm],
    )
    toc.setStyle(TableStyle([
        ("FONT", (0, 0), (-1, -1), "Helvetica", 9.5),
        ("TEXTCOLOR", (0, 0), (-1, -1), GREY),
        ("TEXTCOLOR", (0, 0), (0, -1), ORANGE),
        ("TEXTCOLOR", (4, 0), (4, -1), ORANGE),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]))
    story += [Spacer(1, 2 * mm), toc, Spacer(1, 6 * mm),
              Paragraph("Diagram sources (Mermaid) live in docs/diagrams/*.mmd next to this PDF and render "
                        "natively on GitLab and GitHub.", small),
              PageBreak()]
    return story


def main() -> None:
    doc = SimpleDocTemplate(str(OUT), pagesize=PAGE, leftMargin=MARGIN, rightMargin=MARGIN,
                            topMargin=MARGIN, bottomMargin=14 * mm,
                            title="Guestbook on AWS: Architecture diagrams", author="Mohamed Samir")
    usable_w = PAGE[0] - 2 * MARGIN
    usable_h = PAGE[1] - MARGIN - 14 * mm
    story = cover()
    for i, (stem, name, text) in enumerate(DIAGRAMS, start=1):
        header = [Paragraph(f"DIAGRAM {i:02d}", num_style), Paragraph(name, title_style),
                  Spacer(1, 2 * mm), Paragraph(text, body_style), Spacer(1, 4 * mm)]
        header_h = 34 * mm + 4 * mm * (len(text) // 260)
        img = fitted_image(RENDERED / f"{stem}.png", usable_w, usable_h - header_h)
        img.hAlign = "CENTER"
        story += [KeepTogether(header + [img])]
        if i < len(DIAGRAMS):
            story.append(PageBreak())
    doc.build(story, onFirstPage=footer, onLaterPages=footer)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
