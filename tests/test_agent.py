"""Agent APIのテスト"""

from fastapi.testclient import TestClient

from agentcore_hands_on.agent import app

client = TestClient(app)


def test_health_check():
    """ヘルスチェックエンドポイントのテスト"""
    response = client.get("/ping")
    assert response.status_code == 200
    assert response.json() == {"status": "healthy"}


def test_invocations_endpoint():
    """invocationsエンドポイントのテスト"""
    request_data = {
        "input": {"prompt": "こんにちは"},
        "session_id": "test-session-123",
    }

    response = client.post("/invocations", json=request_data)

    assert response.status_code == 200
    data = response.json()
    assert "output" in data
    assert "response" in data["output"]
    assert "こんにちは" in data["output"]["response"]
    assert data["session_id"] == "test-session-123"


def test_invocations_without_session_id():
    """session_idなしでのinvocationsエンドポイントのテスト"""
    request_data = {
        "input": {"prompt": "テスト"},
    }

    response = client.post("/invocations", json=request_data)

    assert response.status_code == 200
    data = response.json()
    assert "output" in data
    assert data["session_id"] is None
