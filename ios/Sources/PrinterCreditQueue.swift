import Foundation

/// FF03 credits acknowledge complete FF02 writes and permit the next writes.
/// Bluetooth ATT acknowledgements alone do not describe the printer's buffer.
final class PrinterCreditQueue {
    private struct Job {
        var data: Data
        var sent = 0
        var accepted = 0
        var completed: () -> Void
        var progress: (Int, Int) -> Void
    }
    private var jobs: [Job] = []
    private var outstanding: [Int] = []
    private(set) var credits = 0
    private var mtu = 20
    var canSend: () -> Bool = { true }
    var send: (Data) -> Void = { _ in }

    func start(mtu: Int, credits: Int) {
        reset()
        self.mtu = max(1, mtu)
        self.credits = max(0, credits)
    }
    func enqueue(_ data: Data, progress: @escaping (Int, Int) -> Void = { _,_ in }, completed: @escaping () -> Void = {}) {
        guard !data.isEmpty else { completed(); return }
        jobs.append(Job(data:data, completed:completed, progress:progress))
        pump()
    }
    func grant(_ count: Int) {
        guard count > 0 else { return }
        credits += count
        for _ in 0..<min(count,outstanding.count) {
            let length = outstanding.removeFirst()
            if !jobs.isEmpty { jobs[0].accepted += length }
        }
        if !jobs.isEmpty {
            jobs[0].progress(jobs[0].accepted,jobs[0].data.count)
            if jobs[0].accepted == jobs[0].data.count {
                let done = jobs.removeFirst().completed
                done()
            }
        }
        pump()
    }
    func pump() {
        while credits > 0, !jobs.isEmpty, canSend() {
            let start=jobs[0].sent
            guard start<jobs[0].data.count else { return }
            let end=min(start+mtu,jobs[0].data.count)
            let chunk=jobs[0].data.subdata(in:start..<end)
            jobs[0].sent=end
            outstanding.append(chunk.count)
            credits-=1
            send(chunk)
        }
    }
    func reset() { jobs=[];outstanding=[];credits=0 }
}
