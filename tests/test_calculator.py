"""calculator.pyのテスト"""

import pytest

from uv_python_starter_template.calculator import Calculator, add, divide


def test_add() -> None:
    """add関数のテスト"""
    assert add(2, 3) == 5
    assert add(-1, 1) == 0
    assert add(0.5, 0.5) == 1.0


def test_divide() -> None:
    """divide関数のテスト"""
    assert divide(10, 2) == 5.0
    assert divide(7, 2) == 3.5

    # ゼロ除算のテスト
    with pytest.raises(ValueError, match="Cannot divide by zero"):
        divide(10, 0)


class TestCalculator:
    """Calculatorクラスのテスト"""

    def test_add_method(self) -> None:
        """加算メソッドのテスト"""
        calc = Calculator()
        assert calc.add(5) == 5
        assert calc.add(3) == 8
        assert calc.add(-2) == 6

    def test_reset(self) -> None:
        """リセットメソッドのテスト"""
        calc = Calculator()
        calc.add(10)
        calc.reset()
        assert calc.result == 0
