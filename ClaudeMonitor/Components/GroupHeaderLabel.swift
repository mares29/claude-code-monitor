import SwiftUI

struct GroupHeaderLabel: View {
    let group: InstanceGroup

    var body: some View {
        HStack(spacing: 6) {
            Text(group.displayName)
                .font(.headline)

            if group.instances.count > 1 {
                Text("\(group.activeCount)/\(group.instances.count)")
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
        }
    }
}
