#!/usr/bin/env python3
"""Generate a socket-free executable check from the exact prepared emit method and QA delivery source."""
from pathlib import Path
import argparse
import re


def generate(qa_export,output,old_publish=False):
    source=Path(qa_export)/'Packages/SensenVoiceApple/Sources/SensenVoiceApple'
    text=(source/'VoiceBridge.swift').read_text()
    matches=re.findall(r'    private func emit\(_ data: \[String: Any\]\) \{[\s\S]*?\n    \}',text)
    if len(matches)!=1:raise ValueError('Actual emitter not found uniquely')
    method=matches[0].replace('private func emit','func emit')
    if old_publish:method=method.replace('transport?.publish(stamped)','transport?.publish(data)')
    code='''import Foundation
final class CallbackRegistry {
    static let shared = CallbackRegistry()
    var json = ""
    func emit(_ text: String) { json = text }
}
final class SpyTransport {
    var delivery = VoiceEventDelivery()
    var packets: [Data] = []
    var failures = 0
    func publish(_ event: [String: Any]) {
        do { packets.append(try delivery.enqueue(event, now: 1)) }
        catch { failures += 1 }
    }
}
final class ExactEmitter {
    let transport: SpyTransport? = SpyTransport()
'''+method+'''
}
@main struct EmitChecks {
    static func main() throws {
        var checks=0, failures=0
        func check(_ value: Bool, _ label: String) {
            checks += 1; if !value { failures += 1 }
            print((value ? "PASS " : "FAIL ") + label)
        }
        let emitter=ExactEmitter()
        emitter.emit(["event":"disconnected","session":"qa-fixture","reason":"VOICE_EXPIRED"])
        let callback=try JSONSerialization.jsonObject(with: Data(CallbackRegistry.shared.json.utf8)) as! [String:Any]
        check(callback["qa_native_uptime_ms"] is Double && callback["qa_native_wall_seconds"] is Double,"C callback has both clocks")
        let transport=emitter.transport!
        check(transport.failures == 0 && transport.packets.count == 1,"actual publish argument passes real outbox")
        if let packet=transport.packets.first {
            let fields=String(data:packet,encoding:.utf8)!.split(separator:"|",maxSplits:2)
            let event=try JSONSerialization.jsonObject(with:Data(fields[2].utf8)) as! [String:Any]
            check(event["qa_native_uptime_ms"] as? Double == callback["qa_native_uptime_ms"] as? Double,"UDP payload retains exact uptime")
            check(event["qa_native_wall_seconds"] as? Double == callback["qa_native_wall_seconds"] as? Double,"UDP payload retains exact wall clock")
            check(transport.delivery.poll(now:1.24).packets.isEmpty,"no early retry")
            let retry=transport.delivery.poll(now:1.25)
            check(retry.packets == [packet] && !retry.expired,"real retry keeps original bytes and clocks")
            if CommandLine.arguments.count > 1, let repeated = retry.packets.first {
                let fixture = ["initial": String(data: packet, encoding: .utf8)!, "retry": String(data: repeated, encoding: .utf8)!]
                try JSONSerialization.data(withJSONObject: fixture).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
            }
            transport.delivery.acknowledge(Int64(fields[1])!)
            check(transport.delivery.poll(now:2).packets.isEmpty,"ACK ends retry")
        }
        let invalidValues: [Any] = ["not-a-clock",true,-1.0,Double.nan]
        for invalid in invalidValues {
            var outbox=VoiceEventDelivery()
            do {
                _ = try outbox.enqueue(["event":"error","session":"qa-fixture","qa_native_uptime_ms":invalid,"qa_native_wall_seconds":1.0],now:0)
                check(false,"invalid clock refused")
            } catch { check(true,"invalid clock refused") }
        }
        var outbox=VoiceEventDelivery()
        do {
            _ = try outbox.enqueue(["event":"error","session":"qa-fixture","qa_native_uptime_ms":1.0,"qa_native_wall_seconds":1.0,"token":"fixture-private"],now:0)
            check(false,"credential field stays forbidden")
        } catch { check(true,"credential field stays forbidden") }
        print("EMIT_CHECKS \\(checks) checks, \\(failures) failures; real emitter body/outbox, no socket")
        if failures > 0 { exit(1) }
    }
}
'''
    Path(output).write_text(code)
    return [str(source/'VoiceEventDelivery.swift'),str(source/'VoiceWire.swift'),str(Path(output))]

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--qa-export',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--old-publish',action='store_true')
    a=p.parse_args();print('\n'.join(generate(a.qa_export,a.output,a.old_publish)))
