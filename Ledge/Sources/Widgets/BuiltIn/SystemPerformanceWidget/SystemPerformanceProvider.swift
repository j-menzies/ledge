import Foundation
import os.log

/// Collects system performance metrics (CPU, Memory, Disk) using Darwin APIs.
///
/// Must be `nonisolated` because `host_processor_info` and related calls
/// can block briefly. Callers should dispatch from a background context.
nonisolated class SystemPerformanceProvider: @unchecked Sendable {

    private nonisolated(unsafe) let logger = Logger(subsystem: "com.ledge.app", category: "SystemPerformance")

    struct Metrics: Sendable {
        var cpuUsage: Double = 0        // 0-100%
        var memoryUsed: Double = 0      // GB
        var memoryTotal: Double = 0     // GB
        var memoryPercent: Double = 0   // 0-100%
        var diskUsed: Double = 0        // GB
        var diskTotal: Double = 0       // GB
        var diskPercent: Double = 0     // 0-100%
    }

    // Previous CPU ticks for delta calculation
    private nonisolated(unsafe) var previousCPUInfo: processor_info_array_t?
    private nonisolated(unsafe) var previousCPUInfoCount: mach_msg_type_number_t = 0

    /// Collect current system metrics.
    func collect() -> Metrics {
        var m = Metrics()
        m.cpuUsage = collectCPU()
        (m.memoryUsed, m.memoryTotal, m.memoryPercent) = collectMemory()
        (m.diskUsed, m.diskTotal, m.diskPercent) = collectDisk()
        return m
    }

    // MARK: - CPU

    private func collectCPU() -> Double {
        var numCPUs: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            &cpuInfo,
            &cpuInfoCount
        )

        guard result == KERN_SUCCESS, let info = cpuInfo else {
            logger.debug("Failed to get CPU info: \(result)")
            return 0
        }

        var totalUsage: Double = 0

        if let prev = previousCPUInfo {
            for i in 0..<Int(numCPUs) {
                let offset = Int(CPU_STATE_MAX) * i
                let userDelta = Double(info[offset + Int(CPU_STATE_USER)] - prev[offset + Int(CPU_STATE_USER)])
                let systemDelta = Double(info[offset + Int(CPU_STATE_SYSTEM)] - prev[offset + Int(CPU_STATE_SYSTEM)])
                let niceDelta = Double(info[offset + Int(CPU_STATE_NICE)] - prev[offset + Int(CPU_STATE_NICE)])
                let idleDelta = Double(info[offset + Int(CPU_STATE_IDLE)] - prev[offset + Int(CPU_STATE_IDLE)])

                let total = userDelta + systemDelta + niceDelta + idleDelta
                if total > 0 {
                    totalUsage += ((userDelta + systemDelta + niceDelta) / total) * 100.0
                }
            }
            totalUsage /= Double(numCPUs)

            // Deallocate previous
            let prevSize = vm_size_t(previousCPUInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prev), prevSize)
        }

        previousCPUInfo = cpuInfo
        previousCPUInfoCount = cpuInfoCount

        return totalUsage
    }

    // MARK: - Memory

    private func collectMemory() -> (used: Double, total: Double, percent: Double) {
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)
        let totalGB = totalBytes / (1024 * 1024 * 1024)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            logger.debug("Failed to get memory info: \(result)")
            return (0, totalGB, 0)
        }

        let pageSize = Double(vm_kernel_page_size)
        let activeBytes = Double(stats.active_count) * pageSize
        let wiredBytes = Double(stats.wire_count) * pageSize
        let compressedBytes = Double(stats.compressor_page_count) * pageSize

        let usedBytes = activeBytes + wiredBytes + compressedBytes
        let usedGB = usedBytes / (1024 * 1024 * 1024)
        let percent = (usedBytes / totalBytes) * 100.0

        return (usedGB, totalGB, percent)
    }

    // MARK: - Disk

    private func collectDisk() -> (used: Double, total: Double, percent: Double) {
        let fileManager = FileManager.default
        guard let attrs = try? fileManager.attributesOfFileSystem(forPath: "/"),
              let totalSpace = attrs[.systemSize] as? Int64,
              let freeSpace = attrs[.systemFreeSize] as? Int64 else {
            return (0, 0, 0)
        }

        let totalGB = Double(totalSpace) / (1024 * 1024 * 1024)
        let freeGB = Double(freeSpace) / (1024 * 1024 * 1024)
        let usedGB = totalGB - freeGB
        let percent = (usedGB / totalGB) * 100.0

        return (usedGB, totalGB, percent)
    }
}
