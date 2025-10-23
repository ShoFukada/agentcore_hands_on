"""シンプルな計算機モジュール"""


def add(a: float, b: float) -> int | float:
    """2つの数値を加算"""
    return a + b


def divide(a: float, b: float) -> float:
    """2つの数値を除算"""
    if b == 0:
        raise ValueError("Cannot divide by zero")
    return a / b


class Calculator:
    """計算機クラス"""

    def __init__(self) -> None:
        self.result: float = 0

    def add(self, value: float) -> float:
        """値を加算"""
        self.result += value
        return self.result

    def reset(self) -> None:
        """結果をリセット"""
        self.result = 0
