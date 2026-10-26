"""Visits API: one Lambda function behind an API Gateway HTTP API.

Routes (HTTP API payload format 2.0):
    GET  /health  -> {"status": "ok", "environment": ..., "version": ...}
    GET  /visits  -> {"visits": <int>}
    POST /visits  -> {"visits": <int>}   (atomically increments the counter)

Configuration comes from environment variables set by infra/template.yaml:
    TABLE_NAME   DynamoDB table holding the counter (required)
    APP_ENV      dev | prod
    APP_VERSION  git commit SHA of the deployed build
"""

import json
import logging
import os
from functools import lru_cache

import boto3

LOG = logging.getLogger()
LOG.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

COUNTER_ID = "global"


@lru_cache(maxsize=1)
def _table():
    """Create the DynamoDB Table resource once per execution environment.

    Lambda reuses the environment between invocations, so caching the client
    avoids paying the connection setup cost on every request.
    """
    return boto3.resource("dynamodb").Table(os.environ["TABLE_NAME"])


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def get_visits():
    item = _table().get_item(Key={"pk": COUNTER_ID}).get("Item")
    return int(item["visits"]) if item else 0


def add_visit():
    result = _table().update_item(
        Key={"pk": COUNTER_ID},
        UpdateExpression="ADD visits :one",
        ExpressionAttributeValues={":one": 1},
        ReturnValues="UPDATED_NEW",
    )
    return int(result["Attributes"]["visits"])


def health():
    return {
        "status": "ok",
        "environment": os.environ.get("APP_ENV", "local"),
        "version": os.environ.get("APP_VERSION", "local"),
    }


ROUTES = {
    "GET /health": lambda: health(),
    "GET /visits": lambda: {"visits": get_visits()},
    "POST /visits": lambda: {"visits": add_visit()},
}


def handler(event, context):  # noqa: ARG001 - signature required by Lambda
    route_key = event.get("routeKey", "")
    route = ROUTES.get(route_key)
    if route is None:
        LOG.warning("No route for %s", route_key)
        return _response(404, {"message": "Not found"})
    try:
        return _response(200, route())
    except Exception:  # broad on purpose: never return a stack trace to the caller
        LOG.exception("Request failed for %s", route_key)
        return _response(500, {"message": "Internal error"})
