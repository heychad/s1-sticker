import SwiftUI
import AppKit

/// A plain text editor without completion/writing-tool overlay panels.
struct PlainTextEditor:NSViewRepresentable {
    @Binding var text:String
    var editable=true
    func makeCoordinator()->Coordinator{Coordinator(self)}
    func makeNSView(context:Context)->NSScrollView {
        let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.borderType = .noBorder
        let editor=NSTextView(frame:NSRect(x:0,y:0,width:400,height:300))
        editor.isRichText=false;editor.importsGraphics=false;editor.allowsUndo=true
        editor.font = .monospacedSystemFont(ofSize:14,weight:.regular)
        editor.textContainerInset=NSSize(width:8,height:8)
        editor.isVerticallyResizable=true;editor.isHorizontallyResizable=false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView=true
        editor.textContainer?.containerSize=NSSize(width:400,height:CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticTextCompletionEnabled=false
        editor.isAutomaticTextReplacementEnabled=false
        editor.isAutomaticQuoteSubstitutionEnabled=false
        editor.isAutomaticDashSubstitutionEnabled=false
        editor.isAutomaticSpellingCorrectionEnabled=false
        if #available(macOS 15.0,*){editor.writingToolsBehavior = .none}
        editor.delegate=context.coordinator;editor.string=text
        scroll.documentView=editor;return scroll
    }
    func updateNSView(_ scroll:NSScrollView,context:Context) {
        context.coordinator.parent=self
        guard let editor=scroll.documentView as? NSTextView else{return}
        editor.isEditable=editable
        if editor.string != text {
            let old=editor.selectedRange();editor.string=text
            editor.setSelectedRange(NSRange(location:min(old.location,(text as NSString).length),length:0))
        }
    }
    final class Coordinator:NSObject,NSTextViewDelegate {
        var parent:PlainTextEditor
        init(_ parent:PlainTextEditor){self.parent=parent}
        func textDidChange(_ notification:Notification){if let view=notification.object as? NSTextView,parent.text != view.string{parent.text=view.string}}
    }
}

extension View {
    @ViewBuilder func disableWritingOverlays()->some View {
        if #available(macOS 15.0,*){self.writingToolsBehavior(.disabled)}else{self}
    }
}
