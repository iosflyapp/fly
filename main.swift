import SwiftUI

@main
struct CloudTestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var count = 0
    @State private var bgColor = Color.black
    
    var body: some View {
        ZStack {
            // Background Layer
            bgColor.ignoresSafeArea()
            
            VStack(spacing: 30) {
                Image(systemName: "cloud.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                    .shadow(radius: 10)
                
                Text("It Works!")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .foregroundColor(.green)
                
                Text("You are running live on a\nCloud Simulator.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.gray)
                
                // Interactive Counter
                VStack(spacing: 15) {
                    Text("Taps: \(count)")
                        .font(.title)
                        .monospacedDigit()
                        .foregroundColor(.white)
                    
                    Button(action: {
                        count += 1
                        // Change background randomly on every 5th tap
                        if count % 5 == 0 {
                            bgColor = [Color.blue, Color.purple, Color.red, Color.gray].randomElement()!
                        }
                    }) {
                        Text("Tap Me")
                            .font(.headline)
                            .padding()
                            .frame(width: 200)
                            .background(Color.white)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(20)
            }
            .padding()
        }
    }
}
