import SwiftUI

struct WidgetHeaderView<LeadingContent: View, ExtraContent: View>: View {
    @Binding var widgetType: WidgetType
    var leadingButtons: LeadingContent
    var extraButtons: ExtraContent

    init(
        widgetType: Binding<WidgetType>,
        @ViewBuilder leadingButtons: () -> LeadingContent,
        @ViewBuilder extraButtons: () -> ExtraContent
    ) {
        self._widgetType = widgetType
        self.leadingButtons = leadingButtons()
        self.extraButtons = extraButtons()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    leadingButtons
                    Spacer()
                    extraButtons
                }
                Menu {
                    ForEach(WidgetType.allCases) { type in
                        Button(type.rawValue) { widgetType = type }
                    }
                } label: {
                    Text(widgetType.rawValue)
                        .font(.system(size: 11, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(.white, ignoresSafeAreaEdges: [])
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                Color(red: 0xE5/255.0, green: 0xE5/255.0, blue: 0xE5/255.0)
                    .frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }
}

extension WidgetHeaderView where LeadingContent == EmptyView {
    init(widgetType: Binding<WidgetType>, @ViewBuilder extraButtons: () -> ExtraContent) {
        self._widgetType = widgetType
        self.leadingButtons = EmptyView()
        self.extraButtons = extraButtons()
    }
}

extension WidgetHeaderView where LeadingContent == EmptyView, ExtraContent == EmptyView {
    init(widgetType: Binding<WidgetType>) {
        self._widgetType = widgetType
        self.leadingButtons = EmptyView()
        self.extraButtons = EmptyView()
    }
}
