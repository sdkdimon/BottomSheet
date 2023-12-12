//
//  BottomSheet.swift
//
//
//  Created by Wouter van de Kamp on 26/11/2022.
//

import SwiftUI

public struct SheetPlus<HContent: View, MContent: View, Background: View>: ViewModifier, KeyboardReader {
    @Binding private var isPresented: Bool
    @State private var translation: CGFloat = 0
    @State private var sheetConfig: SheetPlusConfig?
    @State private var showDragIndicator: VisibilityPlus?
    @State private var allowBackgroundInteraction: PresentationBackgroundInteractionPlus?
    
    @State private var newValue = 0.0
    
    @State private var detents: Set<PresentationDetent> = []
    @State private var limits: (min: CGFloat, max: CGFloat) = (min: 0, max: 0)
    @State private var translationBeforeKeyboard: CGFloat = 0
    
    let mainContent: MContent
    let headerContent: HContent
    let animationCurve: SheetAnimation
    let onDismiss: () -> Void
    let onDrag: (CGFloat) -> Void
    let background: Background
    
    public init(
        isPresented: Binding<Bool>,
        animationCurve: SheetAnimation,
        background: Background,
        onDismiss: @escaping () -> Void,
        onDrag: @escaping (CGFloat) -> Void,
        @ViewBuilder hcontent: () -> HContent,
        @ViewBuilder mcontent: () -> MContent
    ) {
        self._isPresented = isPresented
        
        self.animationCurve = animationCurve
        self.background = background
        self.onDismiss = onDismiss
        self.onDrag = onDrag
        
        self.headerContent = hcontent()
        self.mainContent = mcontent()
    }
    
    var animation: Animation {
        get {
            .interpolatingSpring(
                mass: animationCurve.mass,
                stiffness: animationCurve.stiffness,
                damping: animationCurve.damping
            )
        }
    }
    
    var drag: some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                withAnimation(self.animation) {
                    translation -= value.translation.height - newValue
                    newValue = value.translation.height
                }
            }
            .onEnded { value in
                // Reset the distance on release so we start with a
                // clean translation next time
                newValue = 0
                if translation <= limits.min * 0.65 {
                    self.isPresented = false
                    return
                }
                
                let yVelocity: CGFloat = -1 * value.velocity.height / 1000
                if yVelocity < 0 && yVelocity < -2.3 {
                    self.isPresented = false
                    return
                }
                
                if let result = snapBottomSheet(translation, detents, yVelocity) {
                    withAnimation(self.animation) {
                        translation = result.size
                        sheetConfig?.selectedDetent = result
                    }
                }
            }
    }
    
    var dragIndicator: some View {
        DragIndicator(
            animation: self.animation,
            translation: $translation,
            detents: detents
        )
        .frame(height: showDragIndicator == .visible ? 22 : 0)
        .opacity(showDragIndicator == .visible ? 1 : 0)
    }
    
    public func body(content: Content) -> some View {
        ZStack {
            content
                .allowsHitTesting(allowBackgroundInteraction == .disabled ? false : true)
            ZStack {
                if isPresented {
                    GeometryReader { geometry in
                        VStack(spacing: 0) {
                            self.dragIndicator
                            self.headerContent
                                .contentShape(Rectangle())
                                .gesture(self.drag)
                            self.mainContent
                                .frame(width: geometry.size.width)
                        }
                        .background(self.background)
                        .frame(height: self.translation)
                        .onAnimationChange(of: translation) { value in
                            onDrag(value)
                        }
                        .offset(y: geometry.size.height - translation)
                        .onDisappear {
                            translation = 0
                            detents = []
                            
                            onDismiss()
                        }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .bottom)))
                    .edgesIgnoringSafeArea([.bottom])
                }
            }
        }
        .zIndex(0)
        .animation(
            self.animation,
            value: self.isPresented
        )
        
        .onPreferenceChange(SheetPlusKey.self) { value in
            /// Quick hack to prevent the scrollview from resetting the height when keyboard shows up.
            /// Replace if the root cause has been located.
            if value.detents.count == 0 { return }
                                                
            sheetConfig = value
            translation = value.translation

            detents = value.detents
            limits = detentLimits(detents: detents)
        }
        .onPreferenceChange(SheetPlusIndicatorKey.self) { value in
            showDragIndicator = value
        }
        .onPreferenceChange(SheetPlusBackgroundInteractionKey.self) { value in
            allowBackgroundInteraction = value
        }
        .onReceive(self.keyboardPublisher) { willShow in
            withAnimation(self.animation) {
                self.translation = willShow ? self.limits.max : self.limits.min
            }
        }
    }
}
