import SwiftUI

struct TuffDailyReportView: View {
    let totalScreenTime: String

    var body: some View {
        VStack(spacing: 6) {
            Text("TODAY'S SCREEN TIME")
                .font(.system(size: 11, weight: .bold, design: .default).width(.condensed))
                .foregroundColor(Color(red: 136/255, green: 136/255, blue: 136/255))
                .tracking(1.2)

            Text(totalScreenTime)
                .font(.system(size: 44, weight: .black, design: .default).width(.condensed))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(red: 26/255, green: 26/255, blue: 26/255))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
