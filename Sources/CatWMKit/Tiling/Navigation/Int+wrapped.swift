extension Int {
    package func wrapped(by delta: Int, in count: Int) -> Int { (self + delta % count + count) % count }
}
