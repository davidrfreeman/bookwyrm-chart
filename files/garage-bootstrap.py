"""Provision buckets and credentials on the bundled testing-only Garage server."""
import json
import os
import ssl
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def request(url, token, body=None, method=None, context=None):
    data = None if body is None else json.dumps(body).encode()
    req = Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token}", "Content-Type": "application/json"})
    with urlopen(req, timeout=15, context=context) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def provision(api, assets, exports, public_host, key_name):
    # Never import fabricated keys: let Garage generate valid key identifiers.
    keys = api("ListKeys")
    existing = next((key for key in keys if key["name"] == key_name and not key["expired"]), None)
    if existing:
        key = api("GetKeyInfo", query={"id": existing["id"], "showSecretKey": "true"})
    else:
        key = api("CreateKey", {"name": key_name})
    for name, public in ((assets, True), (exports, False)):
        buckets = api("ListBuckets")
        bucket = next((bucket for bucket in buckets if name in bucket["globalAliases"]), None)
        if bucket is None:
            bucket = api("CreateBucket", {"globalAlias": name})
        api("AllowBucketKey", {"bucketId": bucket["id"], "accessKeyId": key["accessKeyId"],
                              "permissions": {"read": True, "write": True, "owner": False}})
        if public:
            info = api("GetBucketInfo", query={"id": bucket["id"]})
            if public_host not in info["globalAliases"]:
                api("AddBucketAlias", {"bucketId": bucket["id"], "globalAlias": public_host})
        website = {"enabled": True, "indexDocument": "index.html"} if public else {"enabled": False}
        settings = {"websiteAccess": website}
        if public:
            settings["corsRules"] = [{"AllowedOrigin": ["*"], "AllowedMethod": ["GET", "HEAD"],
                                      "AllowedHeader": ["*"]}]
        api("UpdateBucket", settings, query={"id": bucket["id"]})
    return {"AWS_ACCESS_KEY_ID": key["accessKeyId"], "AWS_SECRET_ACCESS_KEY": key["secretAccessKey"]}


def main():
    admin_token = Path("/garage/admin-token").read_text().strip()
    base = os.environ["GARAGE_ADMIN_URL"]

    def api(operation, body=None, query=None):
        suffix = "?" + urlencode(query) if query else ""
        return request(f"{base}/v2/{operation}{suffix}", admin_token, body)

    deadline = time.monotonic() + 300
    while True:
        try:
            # Single-node mode assigns its own layout; wait for it to become healthy.
            with urlopen(f"{base}/health", timeout=5):
                break
        except (HTTPError, URLError, TimeoutError):
            if time.monotonic() >= deadline:
                raise RuntimeError("Garage did not become healthy within 300 seconds") from None
            print("Waiting for Garage...", flush=True)
            time.sleep(5)
    credentials = provision(api, os.environ["ASSET_BUCKET"], os.environ["EXPORT_BUCKET"],
                            os.environ["ASSET_HOST"], os.environ["KEY_NAME"])
    sa = Path("/var/run/secrets/kubernetes.io/serviceaccount")
    token = (sa / "token").read_text().strip()
    namespace = (sa / "namespace").read_text().strip()
    host = os.environ["KUBERNETES_SERVICE_HOST"]
    port = os.environ["KUBERNETES_SERVICE_PORT"]
    url = f"https://{host}:{port}/api/v1/namespaces/{namespace}/secrets/{os.environ['CREDENTIAL_SECRET']}"
    # Merge-patch only the credentials. Never print keys or tokens.
    req = Request(url, data=json.dumps({"stringData": credentials}).encode(), method="PATCH", headers={
        "Authorization": f"Bearer {token}", "Content-Type": "application/merge-patch+json"})
    with urlopen(req, timeout=15, context=ssl.create_default_context(cafile=str(sa / "ca.crt"))):
        pass
    print("Garage asset and private export buckets are ready.", flush=True)


if __name__ == "__main__":
    main()
