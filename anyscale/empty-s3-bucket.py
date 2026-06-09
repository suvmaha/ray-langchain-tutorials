#!/usr/bin/env python3
"""Delete all versions and delete markers from a versioned S3 bucket.

Usage:
    python3 anyscale/empty-s3-bucket.py <bucket-name>

The bucket itself is not removed — only its contents. Run
`aws s3 rb s3://<bucket>` afterwards to delete the bucket.
"""
import json
import subprocess
import sys


def list_versions(bucket, token=None):
    cmd = ["aws", "s3api", "list-object-versions", "--bucket", bucket, "--output", "json"]
    if token:
        cmd += ["--next-token", token]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout.strip()
    return json.loads(out) if out else {}


def delete_batch(bucket, objects):
    subprocess.run(
        ["aws", "s3api", "delete-objects", "--bucket", bucket,
         "--delete", json.dumps({"Objects": objects, "Quiet": True})],
        check=True, capture_output=True,
    )


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <bucket-name>", file=sys.stderr)
        sys.exit(1)

    bucket = sys.argv[1]
    total = 0
    token = None

    while True:
        data = list_versions(bucket, token)
        objects = [
            {"Key": v["Key"], "VersionId": v["VersionId"]}
            for v in data.get("Versions", []) + data.get("DeleteMarkers", [])
        ]
        for i in range(0, len(objects), 1000):
            delete_batch(bucket, objects[i:i + 1000])
        total += len(objects)

        token = data.get("NextVersionIdMarker") or data.get("NextKeyMarker")
        if not token:
            break

    print(f"Deleted {total} versions/markers from s3://{bucket}")


if __name__ == "__main__":
    main()
