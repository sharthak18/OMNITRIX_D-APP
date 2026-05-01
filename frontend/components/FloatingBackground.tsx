'use client';

import { useEffect, useState } from 'react';

const TOKENS = [
  'https://cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons@1a63530/svg/color/eth.svg',
  'https://cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons@1a63530/svg/color/btc.svg',
  'https://cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons@1a63530/svg/color/link.svg',
  'https://cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons@1a63530/svg/color/uni.svg',
  'https://cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons@1a63530/svg/color/aave.svg',
  'https://cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons@1a63530/svg/color/doge.svg',
  'https://cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons@1a63530/svg/color/usdt.svg',
  'https://cdn.jsdelivr.net/gh/atomiclabs/cryptocurrency-icons@1a63530/svg/color/sol.svg'
];

export function FloatingBackground() {
  const [elements, setElements] = useState<{ id: number; tokenUrl: string; left: string; delay: string; duration: string; size: string }[]>([]);

  useEffect(() => {
    // Generate random tokens on client mount to avoid Next.js hydration mismatch
    const newElements = Array.from({ length: 20 }).map((_, i) => ({
      id: i,
      tokenUrl: TOKENS[Math.floor(Math.random() * TOKENS.length)],
      left: `${Math.random() * 95}%`,
      delay: `${Math.random() * 15}s`,
      duration: `${15 + Math.random() * 25}s`,
      size: `${30 + Math.random() * 30}px`
    }));
    setElements(newElements);
  }, []);

  if (elements.length === 0) return null;

  return (
    <div style={{ position: 'fixed', inset: 0, overflow: 'hidden', zIndex: -1, pointerEvents: 'none' }} aria-hidden="true">
      {elements.map((el) => (
        <div
          key={el.id}
          className="bg-token"
          style={{
            left: el.left,
            width: el.size,
            height: el.size,
            animation: `background-drift ${el.duration} linear ${el.delay} infinite`
          }}
        >
          <img 
            src={el.tokenUrl} 
            alt="crypto logo" 
            style={{ width: '100%', height: '100%', objectFit: 'contain', filter: 'drop-shadow(0 4px 12px rgba(0,0,0,0.4))' }} 
          />
        </div>
      ))}
    </div>
  );
}
