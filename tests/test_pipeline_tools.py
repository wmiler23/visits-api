"""Tests for the Python helpers the pipeline runs: the bundler and the change set renderer."""

import zipfile

import package
import render_changeset


def test_bundle_is_deterministic_and_has_handler_at_root(tmp_path):
    first = package.build(tmp_path / "a.zip")
    second = package.build(tmp_path / "b.zip")
    assert first == second
    names = zipfile.ZipFile(tmp_path / "a.zip").namelist()
    assert "handler.py" in names
    assert not any("__pycache__" in n or n.endswith(".pyc") for n in names)


SAMPLE = {
    "Changes": [
        {
            "Type": "Resource",
            "ResourceChange": {
                "Action": "Modify",
                "LogicalResourceId": "DefaultStage",
                "ResourceType": "AWS::ApiGatewayV2::Stage",
                "Replacement": "False",
                "Details": [{"Target": {"Attribute": "Properties", "Name": "DefaultRouteSettings"}}],
            },
        },
        {
            "Type": "Resource",
            "ResourceChange": {
                "Action": "Add",
                "LogicalResourceId": "ErrorAlarm",
                "ResourceType": "AWS::CloudWatch::Alarm",
            },
        },
        {
            "Type": "Resource",
            "ResourceChange": {
                "Action": "Modify",
                "LogicalResourceId": "VisitsTable",
                "ResourceType": "AWS::DynamoDB::Table",
                "Replacement": "True",
                "Details": [{"Target": {"Attribute": "Properties", "Name": "KeySchema"}}],
            },
        },
    ]
}


def test_render_summarises_counts_and_flags_replacements():
    md = render_changeset.render(SAMPLE, commit="abc1234")
    assert "**3 resource change(s):** 1 add, 2 modify, 0 remove." in md
    assert "**1 replacement(s)" in md
    assert "| Modify | `VisitsTable` | AWS::DynamoDB::Table | **Yes** | `KeySchema` |" in md
    assert "| Add | `ErrorAlarm` | AWS::CloudWatch::Alarm | - | - |" in md
    assert "`abc1234`" in md


def test_render_handles_empty_change_set():
    assert render_changeset.render({"Changes": []}) == "No resource changes.\n"
