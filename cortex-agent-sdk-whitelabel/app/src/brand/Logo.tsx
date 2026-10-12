import type { BrandConfig } from "./brand.config";

export type ThinkingState = "idle" | "submitting" | "thinking" | "streaming" | "done";

/** "Spark-and-settle": the accent chevron detaches from the mark, orbits it trailed by two
 *  fading dots while the agent works, then settles back into the crossbar with a brief glow.
 *  Pure SVG + CSS keyframes (styles.css), colors from theme variables. Reduced motion => pulse. */
export function ThinkingLogo({ brand, state, size = 40 }: { brand: BrandConfig; state: ThinkingState; size?: number }) {
  const { mark } = brand;
  const { cx, cy, r } = mark.orbit;
  return (
    <svg className={`thinking-logo tl-${state}`} width={size} height={size} viewBox={`-8 -8 80 80`} role="img" aria-label={state === "idle" || state === "done" ? brand.productName : `${brand.productName} is working`} data-testid="thinking-logo" data-state={state}>
      <path d={mark.basePath} className="tl-base" />
      <g className="tl-orbit" style={{ transformOrigin: `${cx}px ${cy}px` }}>
        <circle className="tl-dot tl-dot1" cx={cx} cy={cy - r} r={3.2} style={{ transformOrigin: `${cx}px ${cy}px` }} />
        <circle className="tl-dot tl-dot2" cx={cx} cy={cy - r} r={2.4} style={{ transformOrigin: `${cx}px ${cy}px` }} />
        <g className="tl-accent-wrap" style={{ ["--detach" as string]: `${-(r + 4)}px` }}>
          <path d={mark.accentPath} className="tl-accent" strokeWidth={mark.accentWidth} />
        </g>
      </g>
    </svg>
  );
}

export function BrandLogo({ brand, dark, height = 28 }: { brand: BrandConfig; dark: boolean; height?: number }) {
  return <img src={dark ? brand.logo.dark : brand.logo.light} alt={brand.companyName} height={height} style={{ display: "block" }} />;
}

export function ProductLabel({ brand }: { brand: BrandConfig }) {
  return (
    <span className="product-label">
      <span className="pl-prefix">{brand.productPrefix}</span> <span className="pl-suffix">{brand.productSuffix}</span>
    </span>
  );
}
