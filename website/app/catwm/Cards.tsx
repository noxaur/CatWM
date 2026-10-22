import { type CSSProperties, type ReactNode } from "react";

import { CARDS } from "./cards";
import { Demo } from "./Demo";

// The feature cards. Each one sticks at the top and the next slides over it,
// so the page reads as a deck of the four windows.
export function Cards({ last }: { last: ReactNode }) {
  return (
    <>
      {CARDS.map((card, i) => (
        <section
          key={card.id}
          className="card"
          style={{ "--card": card.color, "--i": i + 1 } as CSSProperties}
        >
          <div className="card__inner">
            <div className="card__copy">
              <h2 className="card__title">{card.title}</h2>
              <p className="card__line">{card.line}</p>
            </div>
            <Demo card={card} />
          </div>
        </section>
      ))}
      <section className="card card--last" style={{ "--i": CARDS.length + 1 } as CSSProperties}>
        <div className="card__inner card__inner--center">{last}</div>
      </section>
    </>
  );
}
