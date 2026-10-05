import Foundation

@main
enum Main {
    static func main() {
        switch WindowSnapshot.folder(from: CommandLine.arguments) {
        case .success(let folder):
            exit(MainActor.assumeIsolated { WindowSnapshot.run(folder: folder) })
        case .failure(let error):
            FileHandle.standardError.write(Data((error.message + "\n").utf8))
            exit(64)
        case nil:
            break
        }
        if CommandLine.arguments.contains(UpdateCommand.flag) {
            Task {
                exit(await UpdateCommand.run())
            }
            dispatchMain()
        }
        guard let command = HelperCommand(arguments: CommandLine.arguments) else {
            LidAwakeApp.main()
            return
        }
        Task { @MainActor in
            exit(await command.run())
        }
        dispatchMain()
    }
}
