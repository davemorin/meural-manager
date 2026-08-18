import SwiftUI

struct PhotoGridCell: View {
  var photo: MeuralPhoto
  var showsSelection = false
  var isSelected = false
  var sizeLabel: String?

  var body: some View {
    Color(.secondarySystemBackground)
      .aspectRatio(1, contentMode: .fit)
      .overlay {
        AsyncImage(url: photo.thumbnailURL) { image in
          image
            .resizable()
            .scaledToFill()
        } placeholder: {
          Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.tertiary)
        }
      }
      .clipped()
      .overlay(alignment: .bottomLeading) {
        if let sizeLabel {
          Text(sizeLabel)
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(4)
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if showsSelection {
          Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.black.opacity(0.4)))
            .padding(6)
        }
      }
      .overlay {
        if showsSelection && isSelected {
          Rectangle()
            .strokeBorder(.tint, lineWidth: 3)
        }
      }
      .contentShape(Rectangle())
      .accessibilityLabel(photo.displayName)
      .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
