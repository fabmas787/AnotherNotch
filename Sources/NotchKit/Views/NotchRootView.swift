import SwiftUI

public struct NotchRootView: View {
    @ObservedObject public var viewModel: NotchViewModel
    @Namespace private var notchNamespace

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
    }

    private var isExpanded: Bool {
        viewModel.isExpanded
    }

    private var containerAnimation: Animation {
        isExpanded
            ? .spring(response: 0.42, dampingFraction: 0.80, blendDuration: 0.0)
            : .spring(response: 0.45, dampingFraction: 1.00, blendDuration: 0.0)
    }

    private var geometry: NotchGeometry {
        viewModel.screenManager.currentGeometry
    }

    public var activeWidth: CGFloat {
        isExpanded ? geometry.expandedSize.width : geometry.compactSize.width
    }

    public var activeHeight: CGFloat {
        isExpanded ? geometry.expandedSize.height : geometry.compactSize.height
    }

    private var cornerRadius: CGFloat {
        isExpanded ? 20.0 : 16.0
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Morphing Liquid Glass Shell
            ZStack(alignment: .top) {
                // Background material & specular sheen
                LiquidGlassBackground(
                    isExpanded: isExpanded,
                    hasPhysicalNotch: geometry.hasPhysicalNotch
                )

                // Interior Content with smooth transition
                if isExpanded {
                    ExpandedNotchView(viewModel: viewModel, namespace: notchNamespace)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.80, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.35, dampingFraction: 1.0, blendDuration: 0.0)),
                            removal: .scale(scale: 0.80, anchor: .top)
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.30, dampingFraction: 1.0, blendDuration: 0.0))
                        ))
                } else {
                    CompactNotchView(viewModel: viewModel, namespace: notchNamespace)
                        .transition(.opacity.animation(.easeOut(duration: 0.15)))
                }
            }
            .frame(width: activeWidth, height: activeHeight)
            .contentShape(AppleNotchShape(topRadius: cornerRadius, bottomRadius: cornerRadius))
            .onHover { isHovered in
                if isHovered {
                    viewModel.onMouseEnter()
                } else {
                    viewModel.onMouseExit()
                }
            }
            .animation(containerAnimation, value: isExpanded)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
