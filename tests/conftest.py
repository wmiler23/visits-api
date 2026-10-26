import os

import boto3
import pytest
from moto import mock_aws

TABLE_NAME = "visits-test-visits"


@pytest.fixture(autouse=True)
def aws_env(monkeypatch):
    """Fake credentials and config so no test can ever reach a real AWS account."""
    monkeypatch.setenv("AWS_ACCESS_KEY_ID", "testing")
    monkeypatch.setenv("AWS_SECRET_ACCESS_KEY", "testing")
    monkeypatch.setenv("AWS_SESSION_TOKEN", "testing")
    monkeypatch.setenv("AWS_DEFAULT_REGION", "us-east-1")
    monkeypatch.delenv("AWS_PROFILE", raising=False)
    monkeypatch.setenv("TABLE_NAME", TABLE_NAME)
    monkeypatch.setenv("APP_ENV", "test")
    monkeypatch.setenv("APP_VERSION", "abc123")


@pytest.fixture
def table():
    """A moto-backed DynamoDB table shaped like the one in infra/template.yaml."""
    import handler

    with mock_aws():
        handler._table.cache_clear()
        ddb = boto3.resource("dynamodb", region_name=os.environ["AWS_DEFAULT_REGION"])
        tbl = ddb.create_table(
            TableName=TABLE_NAME,
            BillingMode="PAY_PER_REQUEST",
            AttributeDefinitions=[{"AttributeName": "pk", "AttributeType": "S"}],
            KeySchema=[{"AttributeName": "pk", "KeyType": "HASH"}],
        )
        yield tbl
        handler._table.cache_clear()
