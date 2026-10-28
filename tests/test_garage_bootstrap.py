import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("bootstrap", Path(__file__).parents[1] / "files/garage-bootstrap.py")
bootstrap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bootstrap)


class GarageAPI:
    """In-memory contract fixture for the documented Garage v2 admin endpoints."""
    def __init__(self):
        self.keys = []
        self.buckets = {}
        self.permissions = {}
        self.created_keys = 0

    def __call__(self, operation, body=None, query=None):
        if operation == "ListKeys":
            return [{"id": key["accessKeyId"], "name": key["name"], "expired": False} for key in self.keys]
        if operation == "CreateKey":
            self.created_keys += 1
            key = {"accessKeyId": "GK-generated-by-server", "secretAccessKey": "server-secret", "name": body["name"]}
            self.keys.append(key)
            return key
        if operation == "GetKeyInfo":
            assert query["showSecretKey"] == "true"
            return next(key for key in self.keys if key["accessKeyId"] == query["id"])
        if operation == "ListBuckets":
            return list(self.buckets.values())
        if operation == "CreateBucket":
            bucket = {"id": str(len(self.buckets)), "globalAliases": [body["globalAlias"]]}
            self.buckets[bucket["id"]] = bucket
            return bucket
        if operation == "GetBucketInfo":
            return self.buckets[query["id"]]
        if operation == "AllowBucketKey":
            self.permissions[body["bucketId"]] = body["permissions"]
            assert body["accessKeyId"] == self.keys[0]["accessKeyId"]
            return
        if operation == "AddBucketAlias":
            self.buckets[body["bucketId"]]["globalAliases"].append(body["globalAlias"])
            return
        if operation == "UpdateBucket":
            website = body["websiteAccess"]
            assert not website["enabled"] or website.get("indexDocument")
            self.buckets[query["id"]].update(body)
            return
        raise AssertionError(f"Unexpected API operation: {operation}")


class BootstrapTests(unittest.TestCase):
    def test_fresh_setup_keeps_exports_private_and_allows_asset_reads(self):
        api = GarageAPI()
        credentials = bootstrap.provision(api, "assets", "exports", "assets.example.com", "app")
        self.assertEqual(credentials, {"AWS_ACCESS_KEY_ID": "GK-generated-by-server", "AWS_SECRET_ACCESS_KEY": "server-secret"})
        assets, exports = api.buckets.values()
        self.assertTrue(assets["websiteAccess"]["enabled"])
        self.assertIn("assets.example.com", assets["globalAliases"])
        self.assertEqual(assets["corsRules"][0]["AllowedMethod"], ["GET", "HEAD"])
        self.assertFalse(exports["websiteAccess"]["enabled"])
        self.assertEqual(exports["globalAliases"], ["exports"])
        self.assertEqual(len(api.permissions), 2)
        self.assertTrue(all(not p["owner"] and p["read"] and p["write"] for p in api.permissions.values()))

    def test_upgrade_reuses_credentials_and_buckets(self):
        api = GarageAPI()
        first = bootstrap.provision(api, "assets", "exports", "assets.example.com", "app")
        second = bootstrap.provision(api, "assets", "exports", "assets.example.com", "app")
        self.assertEqual(first, second)
        self.assertEqual(api.created_keys, 1)
        self.assertEqual(len(api.buckets), 2)
        self.assertEqual(api.buckets["0"]["globalAliases"].count("assets.example.com"), 1)

    def test_retry_after_partial_setup_does_not_rotate_keys(self):
        api = GarageAPI()
        original = api.__call__
        def interrupted(operation, body=None, query=None):
            if operation == "AllowBucketKey":
                raise RuntimeError("simulated interruption")
            return original(operation, body, query)
        with self.assertRaises(RuntimeError):
            bootstrap.provision(interrupted, "assets", "exports", "assets.example.com", "app")
        bootstrap.provision(api, "assets", "exports", "assets.example.com", "app")
        self.assertEqual(api.created_keys, 1)
        self.assertEqual(len(api.buckets), 2)


if __name__ == "__main__":
    unittest.main()
