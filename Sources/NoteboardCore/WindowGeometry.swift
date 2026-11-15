import CoreGraphics

/// 노트 창 크기·위치 계산.
public enum WindowGeometry {
    public static let minimumSize = CGSize(width: 260, height: 140)
    public static let sidebarWidth: CGFloat = 220
    public static let cascadeStep: CGFloat = 22

    /// 기본 크기: 화면 가로 1/4 × 세로 1/4.
    public static func defaultSize(screenFrame: CGRect) -> CGSize {
        CGSize(width: max(minimumSize.width, (screenFrame.width / 4).rounded(.down)),
               height: max(minimumSize.height, (screenFrame.height / 4).rounded(.down)))
    }

    /// 화면 크기를 넘지 않게 줄인다(외장 모니터에서 저장한 크기를 맥북 화면에 띄울 때).
    public static func clamped(_ size: CGSize, to visibleFrame: CGRect) -> CGSize {
        CGSize(width: min(max(size.width, minimumSize.width), visibleFrame.width),
               height: min(max(size.height, minimumSize.height), visibleFrame.height))
    }

    /// 새 창의 왼쪽 아래 꼭짓점. 화면 가운데에 두고, 같은 자리에 이미 창이 있으면 오른쪽 아래로 비켜 놓는다.
    /// (AppKit 좌표: y 가 위로 커진다.)
    public static func origin(for size: CGSize, in visibleFrame: CGRect, occupied: [CGPoint]) -> CGPoint {
        let center = CGPoint(x: (visibleFrame.midX - size.width / 2).rounded(),
                             y: (visibleFrame.midY - size.height / 2).rounded())
        var candidate = center
        var tries = 0
        while occupied.contains(where: { abs($0.x - candidate.x) < 2 && abs($0.y - candidate.y) < 2 }), tries < 50 {
            candidate.x += cascadeStep
            candidate.y -= cascadeStep
            // 화면 밖으로 나가면 처음 자리 근처로 되돌아간다.
            if candidate.x + size.width > visibleFrame.maxX || candidate.y < visibleFrame.minY {
                candidate = CGPoint(x: center.x + CGFloat(tries % 5) * 4, y: center.y + CGFloat(tries % 5) * 4)
            }
            tries += 1
        }
        return candidate
    }

    /// 사이드바를 열 때: 편집 영역은 그 자리에 두고 왼쪽으로 사이드바 폭만큼 넓힌다.
    /// 화면 왼쪽 끝에 닿으면 오른쪽으로 민다.
    public static func expandedForSidebar(_ frame: CGRect, visibleFrame: CGRect, width: CGFloat = sidebarWidth) -> CGRect {
        var f = frame
        f.origin.x -= width
        f.size.width += width
        if f.minX < visibleFrame.minX { f.origin.x = visibleFrame.minX }
        return f
    }

    /// 사이드바를 닫을 때: 왼쪽에서 사이드바 폭만큼 줄인다.
    public static func collapsedFromSidebar(_ frame: CGRect, width: CGFloat = sidebarWidth) -> CGRect {
        var f = frame
        let w = min(width, max(0, f.width - minimumSize.width))
        f.origin.x += w
        f.size.width -= w
        return f
    }
}
