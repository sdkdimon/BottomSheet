//
//  BottomSheet.swift
//
//
//  Created by Wouter van de Kamp on 26/11/2022.
//

import SwiftUI

struct SheetPlus<HContent: View, MContent: View, Background: View>: ViewModifier, KeyboardReader {
    @Binding private var isPresented: Bool
    @State private var translation: CGFloat = 0
    @State private var sheetConfig: SheetPlusConfig?
    @State private var showDragIndicator: VisibilityPlus?
    @State private var allowBackgroundInteraction: PresentationBackgroundInteractionPlus?
    
    @State private var newValue = 0.0
    @State private var startTime: DragGesture.Value?
    
    @State private var detents: Set<PresentationDetent> = []
    @State private var limits: (min: CGFloat, max: CGFloat) = (min: 0, max: 0)
    @State private var translationBeforeKeyboard: CGFloat = 0
    
    let mainContent: MContent
    let headerContent: HContent
    let animationCurve: SheetAnimation
    let onDismiss: () -> Void
    let onDrag: (CGFloat) -> Void
    let background: Background
    
    init(
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
                    translation -= value.location.y - value.startLocation.y - newValue
                    newValue = value.location.y - value.startLocation.y
                    
                    if startTime == nil {
                        startTime = value
                    }
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
                
                
                
                // Calculate velocity based on pt/s so it matches the UIPanGesture
                let distance: CGFloat = value.translation.height
                //May be crash here
                let time: CGFloat = value.time.timeIntervalSince(startTime!.time)
                
                let yVelocity: CGFloat = -1 * ((distance / time) / 1000)
                if yVelocity < 0 && yVelocity < -2.5 {
                    self.isPresented = false
                    return
                }
                print("yVelocity \(yVelocity)")
                print("yVelocity new \(value.velocity.height / 1000)")
                startTime = nil
                
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
            translation: $translation,
            detents: detents
        )
        .frame(height: showDragIndicator == .visible ? 22 : 0)
        .opacity(showDragIndicator == .visible ? 1 : 0)
    }
    
    func body(content: Content) -> some View {
        ZStack() {
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
                        .onChange(of: translation) { newValue in
                            // Small little hack to make the iOS scroll behaviour work smoothly
                            if limits.max == 0 { return }
                            translation = min(limits.max, newValue)
                            
                            currentGlobalTranslation = translation
                            print("onChange(of: translation) \(newValue)")
                        }
                        .onAnimationChange(of: translation) { value in
                            print("onAnimationChange \(value)")
                            onDrag(value)
                        }
                        .offset(y: geometry.size.height - translation)
                        .onDisappear {
                            translation = 0
                            detents = []
                            
                            onDismiss()
                            print("onDisappear")
                        }                    
                    }
                    .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .bottom)))
                    .edgesIgnoringSafeArea([.bottom])
                }
            }
        }
        .zIndex(0)
        .animation(
            .interpolatingSpring(
                mass: animationCurve.mass,
                stiffness: animationCurve.stiffness,
                damping: animationCurve.damping
            ),
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
        .onChange(of: self.isPresented) { [oldValue = self.isPresented] newValue in
            if oldValue && !newValue {
//                self.translation = 0
            }
        }
        .onReceive(self.keyboardPublisher) { willShow in
            self.translation = willShow ? self.limits.max : self.limits.min
        }
    }
}
