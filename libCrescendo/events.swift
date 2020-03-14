import Foundation

import EndpointSecurityPrivate

extension ESClient {
    func parseProcEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        if let proc: es_process_t = msg.pointee.process?.pointee {
            cEvent.props = getProcessProps(proc: proc, exec: msg.pointee.event.exec)
        }
        callback(cEvent)
    }

    func parseForkEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        let forkedProc: es_event_fork_t = msg.pointee.event.fork
        if let proc = forkedProc.child?.pointee {
            cEvent.props = getProcessProps(proc: proc, exec: msg.pointee.event.exec)
        }
        callback(cEvent)
    }

    // swiftlint:disable:next cyclomatic_complexity
    func parseIPCEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var IPCEvent: Dictionary = [String: String]()

        let conn: es_event_uipc_connect_t = msg.pointee.event.uipc_connect
        var domainString: String
        var typeString: String
        var protoString: String

        switch conn.domain {
        case AF_UNIX:
            domainString = "AF_UNIX"
        case AF_INET:
            domainString = "AF_INET"
        case AF_LOCAL:
            domainString = "AF_LOCAL"
        default:
            domainString = String(conn.domain)
        }

        switch conn.type {
        case SOCK_STREAM:
            typeString = "SOCK_STREAM"
        case SOCK_DGRAM:
            typeString = "SOCK_DGRAM"
        case SOCK_RAW:
            typeString = "SOCK_RAW"
        default:
            typeString = String(conn.type)
        }

        switch conn.protocol {
        case IPPROTO_IP:
            protoString = "IPPROTO_IP"
        case IPPROTO_UDP:
            protoString = "IPPROTO_UDP"
        case IPPROTO_TCP:
            protoString = "IPPROTO_TCP"
        default:
            protoString = String(conn.protocol)
        }

        IPCEvent["domain"] = domainString
        IPCEvent["proto"] = protoString
        IPCEvent["type"] = typeString
        if let file: es_file_t = conn.file?.pointee {
            IPCEvent["path"] = getString(tok: file.path)
        }
        cEvent.props = IPCEvent

        callback(cEvent)
    }

    func parseFileEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var fileEvent: Dictionary = [String: String]()

        if let file: es_file_t = msg.pointee.event.create.destination.new_path.dir?.pointee {
            fileEvent["path"] = getString(tok: file.path)
            fileEvent["size"] = String(file.stat.st_size)
        }
        cEvent.props = fileEvent

        callback(cEvent)
    }

    func parseRenameEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var fileEvent: Dictionary = [String: String]()

        if let file: es_file_t = msg.pointee.event.rename.source?.pointee {
            fileEvent["srcpath"] = getString(tok: file.path)
            fileEvent["srcsize"] = String(file.stat.st_size)
        }
        fileEvent["desttype"] = String(msg.pointee.event.rename.destination_type.rawValue)
        fileEvent["destfile"] = getString(tok: msg.pointee.event.rename.destination.new_path.filename)

        if let dstfile: es_file_t = msg.pointee.event.rename.destination.existing_file?.pointee {
            fileEvent["destdir"] = getString(tok: dstfile.path)
        }

        cEvent.props = fileEvent

        callback(cEvent)
    }

    func parseKextEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var kextEvent: Dictionary = [String: String]()
        kextEvent["identifier"] = getString(tok: msg.pointee.event.kextload.identifier)

        cEvent.props = kextEvent

        callback(cEvent)
    }

    func parseMountEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var mountEvent: Dictionary = [String: String]()

        if var remoteBytes = msg.pointee.event.mount.statfs?.pointee.f_mntonname {
            let remoteName = String(cString: UnsafeRawPointer(&remoteBytes).assumingMemoryBound(to: CChar.self))
            mountEvent["remotename"] = remoteName
        }
        if var localBytes = msg.pointee.event.mount.statfs?.pointee.f_mntonname {
            let localName = String(cString: UnsafeRawPointer(&localBytes).assumingMemoryBound(to: CChar.self))
            mountEvent["localname"] = localName
        }

        cEvent.props = mountEvent

        callback(cEvent)
    }

    func parseUnlinkEvent(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var deleteEvent: Dictionary = [String: String]()

        if let dir = msg.pointee.event.unlink.parent_dir?.pointee.path {
            deleteEvent["dir"] = getString(tok: dir)
        }
        if let path = msg.pointee.event.unlink.target?.pointee.path {
            deleteEvent["path"] = getString(tok: path)
        }

        cEvent.props = deleteEvent

        callback(cEvent)
    }

    func handleBlockAction(msg: UnsafePointer<es_message_t>, cEvent: inout CrescendoEvent) {
        var decision = ES_AUTH_RESULT_ALLOW

        if let proc: es_process_t = msg.pointee.process?.pointee {
            cEvent.props = getProcessProps(proc: proc, exec: msg.pointee.event.exec)
        }

        // bail if we have empty lists
        if blacklist.isEmpty {
            es_respond_auth_result(client!, msg, decision, false)
            return
        }

        // search the blacklist first
        if blacklist.contains(cEvent.processpath) {
            NSLog("BLOCKED: %@", cEvent.processpath)
            decision = ES_AUTH_RESULT_DENY
        }

        // do not cache for now, may consider making this an option
        es_respond_auth_result(client!, msg, decision, false)
    }
}
