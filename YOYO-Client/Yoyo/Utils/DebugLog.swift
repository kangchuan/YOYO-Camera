//
//  DebugLog.swift
//  Yoyo
//
//  统一的调试日志出口。重构 P4。
//
//  背景：项目里有 675 处 `print()`，其中仅 9 处有 `#if DEBUG` 保护。
//  实时分析循环每 2 秒触发一轮，每次都在做大量字符串插值 —— 这在 Debug
//  构建下是必要的排查手段，但在 Release 包里纯属开销。
//
//  用法：把 `print(...)` 换成 `debugLog(...)`。参数是单个字符串表达式，
//  多值拼接用字符串插值：
//      debugLog("加载完成")
//      debugLog("尺寸 \(w)x\(h)，耗时 \(ms) ms")
//      debugLog("[\(tag)] \(message)")
//
//  ── 为什么必须是 @autoclosure，而不是 variadic ──
//
//  最初的写法是 `debugLog(_ items: Any...)` 加空实现，指望优化器把参数构造当死代码删掉。
//  实测**不成立**：Release（-O + wholemodule）下函数体确实变空，但字符串插值照旧执行。
//  用一段只有 3 条日志调用的函数做对照，汇编里两个版本差这么多：
//
//      variadic Any...   函数体 163 行，栈帧 416 字节，StringGuts.grow ×2 + String.append ×5
//      @autoclosure      函数体   8 行，只剩业务算术（adds / b.vs / ret）
//
//  原因：`String.append`、`StringGuts.grow` 这类 Swift 运行时调用带副作用，
//  优化器不会把它们当死代码消除。空函数体只能去掉「打印」这个动作，
//  去不掉「构造待打印字符串」的开销。
//
//  `@autoclosure` 把表达式包成一个闭包。Release 下函数体为空 → 闭包从不被调用
//  → 字符串构造在编译期就整个消失。代价是**参数必须是单个字符串表达式**，
//  多值要自己拼插值（因此全项目的多参调用点都已改成插值写法）。
//

#if DEBUG

/// 调试日志：行为与 `print` 一致（单行 + 换行结尾），仅在 Debug 构建下输出。
///
/// - Parameter message: 待输出的字符串表达式。传表达式本身而非求值结果，
///   这样 Release 构建下整个表达式的求值（含字符串插值）会被优化掉。
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {
    // 注意：这里必须写 Swift.print。
    // 本文件是 P4 批量替换的源头，若写成裸 print( 会被替换脚本一并改名为 debugLog(，
    // 造成无限递归。
    Swift.print(message())
}

#else

/// 调试日志：Release 构建下为空实现。
///
/// `@autoclosure` + 空函数体 = 参数表达式永不被求值，
/// 字符串插值与格式化在编译期即被消除，运行时零开销。
@inline(__always)
func debugLog(_ message: @autoclosure () -> String) {}

#endif
