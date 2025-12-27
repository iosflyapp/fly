import SwiftUI
struct ContentView: View {
    var body: some View {
        VStack {
            Text("Hello from GitHub!")
                .font(.largeTitle)
                .foregroundColor(.green)
            Button("It Works!") {
                print("Tapped")
            }
        }
    }
}