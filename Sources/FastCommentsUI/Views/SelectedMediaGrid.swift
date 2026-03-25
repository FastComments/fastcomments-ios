import SwiftUI
import PhotosUI

/// Grid of selected media items for post creation with remove buttons.
struct SelectedMediaGrid: View {
    @Binding var selectedItems: [PhotosPickerItem]
    @Binding var loadedImages: [UIImage]

    var body: some View {
        if !loadedImages.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(loadedImages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                loadedImages.remove(at: index)
                                if index < selectedItems.count {
                                    selectedItems.remove(at: index)
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                                    .background(Circle().fill(.black.opacity(0.5)))
                            }
                            .offset(x: 4, y: -4)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }
}
