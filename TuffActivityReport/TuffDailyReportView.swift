import SwiftUI

struct TuffDailyReportView: View {
    let totalScreenTime: String

    var body: some View {
        VStack(spacing: 6) {
            Text("TODAY'S SCREEN TIME")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.red)
                .tracking(1.2)

            Text(totalScreenTime)
                .font(.system(size: 48, weight: .black))
                .foregroundColor(.black)

            Text("(REAL DATA FROM EXTENSION)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color.yellow)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
