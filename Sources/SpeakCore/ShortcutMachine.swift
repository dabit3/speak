import Foundation

public struct ShortcutMachine {
    public enum Action: Equatable {
        case startHold, startHandsFree, lock, finish, cancel
    }

    private var pressedAt: TimeInterval?
    private var lastTap: TimeInterval?
    private var handsFree = false
    private var consumedRelease = false

    public init() {}

    public mutating func press(at time: TimeInterval) -> Action? {
        guard pressedAt == nil else { return nil }
        pressedAt = time
        consumedRelease = false
        if handsFree { return nil }
        if let lastTap, time - lastTap < 0.35 {
            self.lastTap = nil
            handsFree = true
            consumedRelease = true
            return .startHandsFree
        }
        lastTap = nil
        return .startHold
    }

    public mutating func release(at time: TimeInterval) -> Action? {
        guard let pressedAt else { return nil }
        self.pressedAt = nil
        if consumedRelease {
            consumedRelease = false
            return nil
        }
        if handsFree {
            handsFree = false
            return .finish
        }
        if time - pressedAt < 0.18 {
            lastTap = time
            return .cancel
        }
        return .finish
    }

    public mutating func space() -> Action? {
        guard pressedAt != nil, !consumedRelease else { return nil }
        consumedRelease = true
        handsFree.toggle()
        return handsFree ? .lock : .finish
    }

    public mutating func enterHandsFree() { handsFree = true }

    public mutating func reset() { self = Self() }
}
