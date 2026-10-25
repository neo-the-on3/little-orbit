import Foundation

/// Stable IDs for one occurrence of a scheduled item (#26, #11). The same item and day always give the same IDs,
/// on every device and after every relaunch, so the recorded transaction and the settled-occurrence record of an
/// occurrence are one record each, even once sync (#21) merges two devices that both recorded it.
///
/// The ID is a 128-bit FNV-1a hash of the item's ID, the day and the record kind, marked as a version 8 UUID
/// (RFC 9562). It's an identity, not a secret.
public enum ScheduledKey {
    public static func transactionID(item: UUID, day: CalendarDay) -> UUID {
        id(item: item, day: day, kind: "transaction")
    }

    public static func occurrenceID(item: UUID, day: CalendarDay) -> UUID {
        id(item: item, day: day, kind: "occurrence")
    }

    private static func id(item: UUID, day: CalendarDay, kind: String) -> UUID {
        var bytes: [UInt8] = withUnsafeBytes(of: item.uuid) { Array($0) }
        bytes += Array("|\(day.year)-\(day.month)-\(day.day)|\(kind)".utf8)
        let high = fnv1a(bytes, basis: 0xcbf2_9ce4_8422_2325)
        let low = fnv1a(bytes.reversed(), basis: 0x8422_2325_cbf2_9ce4)
        var out = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            out[index] = UInt8(truncatingIfNeeded: high >> (56 - 8 * index))
            out[index + 8] = UInt8(truncatingIfNeeded: low >> (56 - 8 * index))
        }
        out[6] = (out[6] & 0x0F) | 0x80
        out[8] = (out[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                out[0], out[1], out[2], out[3], out[4], out[5], out[6], out[7],
                out[8], out[9], out[10], out[11], out[12], out[13], out[14], out[15],
            )
        )
    }

    private static func fnv1a(_ bytes: some Sequence<UInt8>, basis: UInt64) -> UInt64 {
        var hash = basis
        for byte in bytes {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}
