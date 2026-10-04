import Foundation

@main
enum Main {
    static func main() {
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
