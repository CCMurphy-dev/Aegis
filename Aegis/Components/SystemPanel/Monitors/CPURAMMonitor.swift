import Foundation
import Combine

final class CPURAMMonitor: ObservableObject {
    static let shared = CPURAMMonitor()

    @Published var cpuUsage: Float = 0
    @Published var cpuHistory: [Float] = []
    @Published var ramUsage: Float = 0
    @Published var ramHistory: [Float] = []
    @Published var ramUsedGB: Float = 0

    private let config = AegisConfig.shared
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // Previous CPU tick counts for delta calculation
    private var previousUserTicks: UInt64 = 0
    private var previousSystemTicks: UInt64 = 0
    private var previousIdleTicks: UInt64 = 0
    private var previousNiceTicks: UInt64 = 0

    private init() {
        // Observe config toggles to start/stop polling
        Publishers.CombineLatest(config.$showCPUMonitor, config.$showRAMMonitor)
            .removeDuplicates { $0 == $1 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cpu, ram in
                if cpu || ram {
                    self?.start()
                } else {
                    self?.stop()
                }
            }
            .store(in: &cancellables)
    }

    private func start() {
        guard timer == nil else { return }
        // Seed initial tick values
        _ = sampleCPU()
        sample()
        let interval = max(0.5, config.cpuUpdateInterval)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.sample()
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let maxSamples = max(5, config.cpuSampleCount)

        if config.showCPUMonitor {
            let cpu = sampleCPU()
            cpuUsage = cpu
            cpuHistory.append(cpu)
            if cpuHistory.count > maxSamples {
                cpuHistory.removeFirst(cpuHistory.count - maxSamples)
            }
        }

        if config.showRAMMonitor {
            let (usage, usedGB) = sampleRAM()
            ramUsage = usage
            ramUsedGB = usedGB
            ramHistory.append(usage)
            if ramHistory.count > maxSamples {
                ramHistory.removeFirst(ramHistory.count - maxSamples)
            }
        }
    }

    // MARK: - CPU Sampling (mach host_processor_info)

    private func sampleCPU() -> Float {
        let host = mach_host_self()
        var cpuInfoCount: mach_msg_type_number_t = 0
        var cpuInfo: processor_info_array_t?
        var numProcessors: natural_t = 0

        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &numProcessors, &cpuInfo, &cpuInfoCount)
        guard result == KERN_SUCCESS, let info = cpuInfo else { return 0 }

        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(cpuInfoCount) * vm_size_t(MemoryLayout<Int32>.size))
        }

        var totalUser: UInt64 = 0
        var totalSystem: UInt64 = 0
        var totalIdle: UInt64 = 0
        var totalNice: UInt64 = 0

        for i in 0..<Int(numProcessors) {
            let offset = Int(CPU_STATE_MAX) * i
            totalUser += UInt64(info[offset + Int(CPU_STATE_USER)])
            totalSystem += UInt64(info[offset + Int(CPU_STATE_SYSTEM)])
            totalIdle += UInt64(info[offset + Int(CPU_STATE_IDLE)])
            totalNice += UInt64(info[offset + Int(CPU_STATE_NICE)])
        }

        let deltaUser = totalUser - previousUserTicks
        let deltaSystem = totalSystem - previousSystemTicks
        let deltaIdle = totalIdle - previousIdleTicks
        let deltaNice = totalNice - previousNiceTicks

        previousUserTicks = totalUser
        previousSystemTicks = totalSystem
        previousIdleTicks = totalIdle
        previousNiceTicks = totalNice

        let totalDelta = deltaUser + deltaSystem + deltaIdle + deltaNice
        guard totalDelta > 0 else { return 0 }

        return Float(deltaUser + deltaSystem + deltaNice) / Float(totalDelta)
    }

    // MARK: - RAM Sampling (mach host_statistics64)

    private func sampleRAM() -> (usage: Float, usedGB: Float) {
        let host = mach_host_self()
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return (0, 0) }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        let totalBytes = ProcessInfo.processInfo.physicalMemory
        let usage = Float(used) / Float(totalBytes)
        let usedGB = Float(used) / (1024 * 1024 * 1024)

        return (usage, usedGB)
    }

    deinit {
        timer?.invalidate()
    }
}
