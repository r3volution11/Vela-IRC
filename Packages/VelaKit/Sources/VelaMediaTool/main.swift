// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import Foundation
import VelaMedia

let usage = """
    Usage: vela-media-tool <command> [arguments]

    Commands:
      docs                 Print the generated part of the "Supported media sites"
                           page (\(MediaSitesPage.pagePath)), from MediaSites.swift.
      docs --write <page>  Rewrite that part of <page>, between its markers.
      list                 List every site with its link forms and sample links
                           (live samples are marked "live").
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "docs":
    switch arguments.count {
    case 1:
        print(MediaSitesPage.markdown(), terminator: "")
    case 3 where arguments[1] == "--write":
        let url = URL(fileURLWithPath: arguments[2])
        do {
            let page = try String(contentsOf: url, encoding: .utf8)
            let updated = try MediaSitesPage.updating(page)
            if updated != page {
                try updated.write(to: url, atomically: true, encoding: .utf8)
                print("Updated \(arguments[2]).")
            } else {
                print("\(arguments[2]) is up to date.")
            }
        } catch {
            fail("\(arguments[2]): \(error)")
        }
    default:
        fail(usage)
    }

case "list":
    for site in MediaSites.all {
        print("\(site.name) [\(site.id)], \(site.category.rawValue), rule: \(site.ruleDomain ?? "each domain's own")")
        for form in site.forms {
            print("  \(form.pattern)")
            for sample in site.samples where sample.form == form.id {
                print("    \(sample.isLive ? "live   " : "offline") \(sample.link)")
            }
        }
        if let note = site.liveNote { print("  (\(note))") }
    }

default:
    fail(usage)
}
