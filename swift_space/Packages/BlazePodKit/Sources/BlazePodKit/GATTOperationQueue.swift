import CoreBluetooth
import Foundation

/// One-at-a-time GATT operation queue with timeout (`je.q` + `je.m`, ops in `zp.*`).
/// The original advances on every read/write/descriptor callback and cancels an
/// operation that has not completed within 3003 ms.
final class GATTOperationQueue {
    enum Operation {
        case read(service: CBUUID, characteristic: CBUUID, completion: (Data?) -> Void)
        case write(service: CBUUID, characteristic: CBUUID, value: Data)
        case enableNotify(service: CBUUID, characteristic: CBUUID)
    }

    static let timeout: TimeInterval = 3.003

    private let queue: DispatchQueue
    private var pending: [Operation] = []
    private var current: Operation?
    private var timeoutWork: DispatchWorkItem?
    weak var peripheral: CBPeripheral?

    init(queue: DispatchQueue) { self.queue = queue }

    func enqueue(_ op: Operation) {
        pending.append(op)
        runNext()
    }

    func clear() {
        pending.removeAll()
        current = nil
        timeoutWork?.cancel()
    }

    // MARK: Delegate hooks (call from CBPeripheralDelegate on `queue`)

    /// CoreBluetooth funnels reads and notifications through one callback, so only a
    /// value for the characteristic currently being read completes the operation.
    func didRead(_ characteristic: CBCharacteristic, error: Error?) {
        guard case let .read(_, uuid, completion)? = current, uuid == characteristic.uuid else { return }
        completion(error == nil ? characteristic.value : nil)
        complete()
    }

    func didWrite(_ characteristic: CBCharacteristic) { complete() }
    func didUpdateNotificationState(_ characteristic: CBCharacteristic) { complete() }

    // MARK: Private

    private func complete() {
        timeoutWork?.cancel()
        current = nil
        runNext()
    }

    private func runNext() {
        guard current == nil, !pending.isEmpty, let p = peripheral else { return }
        let op = pending.removeFirst()
        current = op

        let work = DispatchWorkItem { [weak self] in self?.complete() } // cancel on timeout
        timeoutWork = work
        queue.asyncAfter(deadline: .now() + Self.timeout, execute: work)

        switch op {
        case let .read(s, c, completion):
            guard let ch = p.characteristic(s, c) else { completion(nil); return complete() }
            p.readValue(for: ch)
        case let .write(s, c, value):
            guard let ch = p.characteristic(s, c) else { return complete() }
            if ch.properties.contains(.write) {
                p.writeValue(value, for: ch, type: .withResponse)
            } else {
                // No callback for write-without-response: advance immediately.
                p.writeValue(value, for: ch, type: .withoutResponse)
                complete()
            }
        case let .enableNotify(s, c):
            guard let ch = p.characteristic(s, c) else { return complete() }
            p.setNotifyValue(true, for: ch)
        }
    }
}

extension CBPeripheral {
    func characteristic(_ service: CBUUID, _ characteristic: CBUUID) -> CBCharacteristic? {
        services?.first { $0.uuid == service }?.characteristics?.first { $0.uuid == characteristic }
    }
}
