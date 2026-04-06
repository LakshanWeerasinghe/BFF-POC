'use client';

import { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { usePathname } from 'next/navigation';

export default function PageTransition({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();

  // Freeze children per route so AnimatePresence exits the OLD route with the
  // OLD page's content. Without this, when children updates before the exit
  // animation completes, the exiting element renders the NEW page — mounting
  // its components and firing data-fetching effects a second time.
  //
  // Render-phase update: when pathname changes, React discards the current
  // render and immediately retries with the new state, ensuring AnimatePresence
  // only ever sees one committed key per navigation.
  const [prevPathname, setPrevPathname] = useState(pathname);
  const [displayChildren, setDisplayChildren] = useState(children);

  if (prevPathname !== pathname) {
    setPrevPathname(pathname);
    setDisplayChildren(children);
  }

  return (
    <AnimatePresence mode="wait">
      <motion.div
        key={prevPathname}
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, y: -10 }}
        transition={{ duration: 0.3 }}
      >
        {displayChildren}
      </motion.div>
    </AnimatePresence>
  );
}
