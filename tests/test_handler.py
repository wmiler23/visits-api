import json

import handler


def call(route_key):
    """Invoke the handler the way API Gateway HTTP API (payload 2.0) does."""
    response = handler.handler({"version": "2.0", "routeKey": route_key}, None)
    return response["statusCode"], json.loads(response["body"])


def test_health_reports_environment_and_version():
    status, body = call("GET /health")
    assert status == 200
    assert body == {"status": "ok", "environment": "test", "version": "abc123"}


def test_visits_start_at_zero(table):
    status, body = call("GET /visits")
    assert status == 200
    assert body == {"visits": 0}


def test_post_increments_and_get_reads_back(table):
    assert call("POST /visits") == (200, {"visits": 1})
    assert call("POST /visits") == (200, {"visits": 2})
    assert call("GET /visits") == (200, {"visits": 2})


def test_unknown_route_returns_404():
    status, body = call("GET /nope")
    assert status == 404
    assert body["message"] == "Not found"


def test_backend_failure_returns_500_without_leaking_details(table, monkeypatch):
    def boom():
        raise RuntimeError("table unavailable: arn:aws:dynamodb:secret")

    monkeypatch.setitem(handler.ROUTES, "GET /visits", boom)
    status, body = call("GET /visits")
    assert status == 500
    assert body == {"message": "Internal error"}


def test_response_is_json_with_content_type():
    response = handler.handler({"routeKey": "GET /health"}, None)
    assert response["headers"]["content-type"] == "application/json"
