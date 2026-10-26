"""tuscenes-prod の全バケットについて CloudWatch の S3 メトリクスを集計する（読み取り専用）。"""
import json
import sys
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import boto3

sess = boto3.Session(profile_name="readonly")
END = datetime.now(timezone.utc)
START = END - timedelta(days=455)

regions = {}
for line in open(sys.argv[1]):
    b, r = line.rstrip("\n").split("\t")
    regions[b] = "us-east-1" if r in ("None", "") else r
metric_filters = {}
for line in open(sys.argv[2]):
    b, ids = line.rstrip("\n").split("\t", 1)
    ids = [i for i in ids.replace("\t", " ").split() if i != "None"]
    if ids:
        metric_filters[b] = ids

_cw = {}


def cw(region):
    if region not in _cw:
        _cw[region] = sess.client("cloudwatch", region_name=region)
    return _cw[region]


def series(region, name, dims, stat):
    res = cw(region).get_metric_statistics(
        Namespace="AWS/S3", MetricName=name, Dimensions=dims,
        StartTime=START, EndTime=END, Period=86400, Statistics=[stat],
    )
    return sorted((p["Timestamp"].date().isoformat(), p[stat]) for p in res["Datapoints"])


def storage_types(region, bucket):
    out = []
    pag = cw(region).get_paginator("list_metrics")
    for page in pag.paginate(Namespace="AWS/S3", MetricName="BucketSizeBytes",
                             Dimensions=[{"Name": "BucketName", "Value": bucket}]):
        for m in page["Metrics"]:
            for d in m["Dimensions"]:
                if d["Name"] == "StorageType":
                    out.append(d["Value"])
    return out


def one(bucket):
    region = regions[bucket]
    r = {"bucket": bucket, "region": region}
    try:
        n = series(region, "NumberOfObjects",
                   [{"Name": "BucketName", "Value": bucket}, {"Name": "StorageType", "Value": "AllStorageTypes"}],
                   "Average")
        r["objects"] = n
        sizes = {}
        for st in storage_types(region, bucket):
            s = series(region, "BucketSizeBytes",
                       [{"Name": "BucketName", "Value": bucket}, {"Name": "StorageType", "Value": st}], "Average")
            if s:
                sizes[st] = s
        r["sizes"] = sizes
        reqs = {}
        for fid in metric_filters.get(bucket, []):
            for m in ("GetRequests", "PutRequests", "HeadRequests", "ListRequests", "BytesDownloaded"):
                s = series(region, m, [{"Name": "BucketName", "Value": bucket}, {"Name": "FilterId", "Value": fid}], "Sum")
                if s:
                    reqs.setdefault(fid, {})[m] = s
        r["requests"] = reqs
    except Exception as e:  # noqa: BLE001
        r["error"] = str(e)
    return r


with ThreadPoolExecutor(16) as ex:
    results = list(ex.map(one, list(regions)))
json.dump(results, open(sys.argv[3], "w"))
print(len(results), "buckets", sum(1 for r in results if "error" in r), "errors")
