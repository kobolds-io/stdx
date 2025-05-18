const std = @import("std");
const assert = std.debug.assert;

const stdx = @import("stdx");
const EventEmitter = stdx.EventEmitter;

const Calculator = struct {
    const Self = @This();
    result: i128 = 0,

    pub fn onAdd(self: *Self, event: Operation, operand: i128) void {
        assert(event == .add);
        self.result += operand;
    }

    pub fn onSubtract(self: *Self, event: Operation, operand: i128) void {
        assert(event == .subtract);
        self.result -= operand;
    }

    pub fn onMultiply(self: *Self, event: Operation, operand: i128) void {
        assert(event == .multiply);
        self.result *= operand;
    }

    pub fn onDivide(self: *Self, event: Operation, operand: i128) void {
        assert(event == .divide);
        assert(operand != 0);
        self.result = @divFloor(self.result, operand);
    }
    pub fn onSetLHS(self: *Self, event: Operation, operand: i128) void {
        assert(event == .set);
        self.result = operand;
    }
};

const Operation = enum {
    add,
    subtract,
    multiply,
    divide,
    set,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var calculator_ee = EventEmitter(Operation, *Calculator, i128).init(allocator);
    defer calculator_ee.deinit();

    var calculator = Calculator{};

    try calculator_ee.addEventListener(&calculator, .add, Calculator.onAdd);
    try calculator_ee.addEventListener(&calculator, .subtract, Calculator.onSubtract);
    try calculator_ee.addEventListener(&calculator, .multiply, Calculator.onMultiply);
    try calculator_ee.addEventListener(&calculator, .divide, Calculator.onDivide);
    try calculator_ee.addEventListener(&calculator, .set, Calculator.onSetLHS);

    calculator_ee.emit(.set, 10);
    assert(calculator.result == 10);

    calculator_ee.emit(.add, 1);
    assert(calculator.result == 11);

    calculator_ee.emit(.subtract, 12);
    assert(calculator.result == -1);

    calculator_ee.emit(.multiply, 100);
    assert(calculator.result == -100);

    calculator_ee.emit(.divide, -10);
    assert(calculator.result == 10);
}
