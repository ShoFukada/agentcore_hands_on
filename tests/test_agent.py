"""Agent APIのテスト"""

from fastapi.testclient import TestClient

from agentcore_hands_on.agent import app

client = TestClient(app)


def test_health_check():
    """ヘルスチェックエンドポイントのテスト"""
    response = client.get("/ping")
    assert response.status_code == 200
    result = response.json()
    assert result["status"] == "Healthy"
    assert "time_of_last_update" in result
