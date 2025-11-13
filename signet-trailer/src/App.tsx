import { motion } from 'motion/react';
import { useState, useEffect } from 'react';
import DemoThread from './components/DemoThread';

const SPEED_MULTIPLIER = 0.5;
const speed = (value: number) => value * SPEED_MULTIPLIER;

export default function App() {
  const letters = "UNBREAK".split("");
  const [isMobile, setIsMobile] = useState(false);
  const [prefersReducedMotion, setPrefersReducedMotion] = useState(false);
  
  // Detect mobile viewport and reduced motion preference
  useEffect(() => {
    const checkMobile = () => {
      setIsMobile(window.innerWidth < 768);
    };
    
    const checkReducedMotion = () => {
      setPrefersReducedMotion(window.matchMedia('(prefers-reduced-motion: reduce)').matches);
    };
    
    checkMobile();
    checkReducedMotion();
    
    window.addEventListener('resize', checkMobile);
    const motionMediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    motionMediaQuery.addEventListener('change', checkReducedMotion);
    
    return () => {
      window.removeEventListener('resize', checkMobile);
      motionMediaQuery.removeEventListener('change', checkReducedMotion);
    };
  }, []);
  
  // Mobile-optimized: no blur filters
  const getLetterAnimations = (index: number) => {
    if (isMobile || prefersReducedMotion) {
      return {
        initial: {
          x: (Math.random() - 0.5) * 800,
          y: (Math.random() - 0.5) * 600,
          rotate: (Math.random() - 0.5) * 720,
          opacity: 0,
          scale: 0.1,
        },
        animate: {
          x: 0,
          y: 0,
          rotate: 0,
          opacity: 1,
          scale: 1,
        },
        transition: {
          duration: speed(1.5),
          delay: index * 0.15 * SPEED_MULTIPLIER,
          ease: [0.22, 1, 0.36, 1],
        }
      };
    }
    
    // Desktop: full cinematic experience - NO BLUR ON TEXT, only glitch
    return {
      initial: {
        x: (Math.random() - 0.5) * 1200,
        y: (Math.random() - 0.5) * 900,
        rotate: (Math.random() - 0.5) * 1080,
        opacity: 0,
        scale: 0.1,
      },
      animate: {
        x: 0,
        y: 0,
        rotate: 0,
        opacity: 1,
        scale: 1,
        filter: [
          'drop-shadow(0px 0px 0px transparent)',
          'drop-shadow(0px 0px 0px transparent)',
          'drop-shadow(0px 0px 0px transparent)',
          'drop-shadow(0px 0px 0px transparent)',
          'drop-shadow(12px 0 0 rgba(255, 255, 0, 1)) drop-shadow(-12px 0 0 rgba(168, 85, 247, 1))',
          'drop-shadow(15px 2px 0 rgba(255, 255, 0, 1)) drop-shadow(-15px -2px 0 rgba(168, 85, 247, 1))',
          'drop-shadow(10px 0 0 rgba(255, 255, 0, 1)) drop-shadow(-10px 0 0 rgba(168, 85, 247, 1))',
          'drop-shadow(4px 0 0 rgba(255, 255, 0, 0.6)) drop-shadow(-4px 0 0 rgba(168, 85, 247, 0.6))',
          'drop-shadow(0px 0px 0px transparent)',
          'drop-shadow(0px 0px 0px transparent)'
        ]
      },
      transition: {
        duration: speed(1.8),
        delay: index * 0.15 * SPEED_MULTIPLIER,
        ease: [0.22, 1, 0.36, 1],
        filter: {
          times: [0, 0.25, 0.5, 0.6, 0.65, 0.7, 0.75, 0.85, 0.95, 1],
          duration: speed(1.8),
          delay: index * 0.15 * SPEED_MULTIPLIER
        }
      }
    };
  };
  
  // Optimized text shadow - yellow glow + chunky shadows
  const getTextShadow = () => {
    if (isMobile) {
      return '0 0 20px rgba(255, 255, 0, 0.6)';
    }
    return `
      0 0 15px rgba(255, 255, 0, 0.8),
      0 0 25px rgba(255, 255, 0, 0.5),
      3px 3px 0px rgba(0, 0, 0, 0.8),
      6px 6px 0px rgba(0, 0, 0, 0.6),
      9px 9px 0px rgba(0, 0, 0, 0.4)
    `;
  };
  
  return (
    <div className="min-h-screen bg-white overflow-x-hidden">
      {/* Header - appears after hero animations */}
      <motion.header
        initial={{ y: -100, opacity: 0 }}
        animate={{ y: 0, opacity: 1 }}
        transition={{ delay: speed(9), duration: speed(0.6), ease: [0.22, 1, 0.36, 1] }}
        className="fixed top-0 left-0 right-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-200"
      >
        <div className="max-w-7xl mx-auto px-4 sm:px-6 py-3 sm:py-4 flex items-center justify-between">
          <a href="#" style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '20px', letterSpacing: '-0.025em' }} className="text-black sm:text-2xl">
            Signet
          </a>
          <nav className="hidden md:flex items-center gap-8">
            <a href="#what-signet-does" style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '500', fontSize: '16px' }} className="text-gray-700 hover:text-black transition-colors">
              What it does
            </a>
            <a href="#how-it-works" style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '500', fontSize: '16px' }} className="text-gray-700 hover:text-black transition-colors">
              How it works
            </a>
            <a href="#faq" style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '500', fontSize: '16px' }} className="text-gray-700 hover:text-black transition-colors">
              FAQ
            </a>
            <a 
              href="mailto:info@signet.ing" 
              style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '600', fontSize: '15px' }}
              className="px-6 py-2 bg-black text-white hover:bg-gray-800 transition-colors"
            >
              Contact Us
            </a>
          </nav>
          <a 
            href="mailto:info@signet.ing" 
            style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '600', fontSize: '14px' }}
            className="md:hidden px-4 py-2 bg-black text-white hover:bg-gray-800 transition-colors whitespace-nowrap"
          >
            Contact
          </a>
        </div>
      </motion.header>

      {/* Hero Section */}
      <div className="min-h-screen flex items-center justify-center relative bg-white">
        {/* Very subtle radial glow - barely visible */}
        <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 2, opacity: 0.015 }}
          transition={{ duration: speed(2), delay: speed(0.5) }}
          className="absolute inset-0 flex items-center justify-center pointer-events-none"
        >
          <div 
            className="w-[800px] h-[800px] rounded-full" 
            style={{
              background: 'radial-gradient(circle, rgba(255, 255, 0, 0.08) 0%, transparent 60%)'
            }}
          />
        </motion.div>
        
        <div className="text-center px-4 relative z-10">
          <div className="flex justify-center items-center flex-wrap gap-1">
            {letters.map((letter, index) => {
              const animations = getLetterAnimations(index);
              return (
                <motion.span
                  key={index}
                  initial={animations.initial}
                  animate={animations.animate}
                  transition={animations.transition}
                  className="text-black inline-block"
                  style={{
                    fontFamily: 'Inter, sans-serif',
                    fontSize: 'clamp(4rem, 15vw, 12rem)',
                    fontWeight: '900',
                    lineHeight: '1',
                    textShadow: getTextShadow(),
                    letterSpacing: '-0.02em'
                  }}
                >
                  {letter}
                </motion.span>
              );
            })}
          </div>
          
          <motion.div
            initial={{ opacity: 0, y: 100, scale: 0.8 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            transition={{
              duration: speed(1.5),
              delay: speed(1.8),
              ease: [0.22, 1, 0.36, 1]
            }}
            className="text-black"
            style={{
              fontFamily: 'Inter, sans-serif',
              fontSize: 'clamp(4rem, 15vw, 12rem)',
              fontWeight: '900',
              lineHeight: '1',
              textShadow: getTextShadow(),
              letterSpacing: '-0.02em'
            }}
          >
            THE<br />INTERNET
          </motion.div>
          
          <motion.div
            initial={{ scaleX: 0 }}
            animate={{ scaleX: 1 }}
            transition={{ delay: speed(2.5), duration: speed(1.2), ease: "easeInOut" }}
            className="h-1 bg-gradient-to-r from-transparent via-black to-transparent mt-16 mb-12 mx-auto max-w-3xl"
          />
          
          <div className="max-w-4xl mx-auto flex flex-col items-center space-y-4 text-center">
            {isMobile || prefersReducedMotion ? (
              <motion.p
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: speed(3.2), duration: speed(1) }}
                className="text-black inline-block relative text-center"
                style={{ fontFamily: 'Urbanist, sans-serif !important', fontSize: 'clamp(1.1rem, 2.5vw, 1.75rem)', lineHeight: '1.4' }}
              >
                <span className="relative z-10 px-2 py-1">
                  The internet has a credibility crisis
                  <br className="sm:hidden" />
                  and polarization problem
                </span>
                <motion.span
                  initial={{ scaleX: 0 }}
                  animate={{ scaleX: 1 }}
                  transition={{ delay: speed(4.2), duration: speed(0.6), ease: "easeOut" }}
                  className="absolute inset-0"
                  style={{ transformOrigin: 'left', zIndex: 0, backgroundColor: 'rgba(255, 255, 0, 1)' }}
                />
              </motion.p>
            ) : (
              <motion.p
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: speed(3.2), duration: speed(1) }}
                className="text-black inline-block relative text-center"
                style={{ fontFamily: 'Urbanist, sans-serif !important', fontSize: 'clamp(1.1rem, 2.5vw, 1.75rem)', lineHeight: '1.4' }}
              >
                <span className="relative z-10 px-2 py-1">
                  The internet has a credibility crisis
                  <br className="sm:hidden" />
                  and polarization problem
                </span>
                <motion.span
                  initial={{ scaleX: 0 }}
                  animate={{ scaleX: 1 }}
                  transition={{ delay: speed(4.2), duration: speed(0.6), ease: "easeOut" }}
                  className="absolute inset-0"
                  style={{ transformOrigin: 'left', zIndex: 0, backgroundColor: 'rgba(255, 255, 0, 1)' }}
                />
              </motion.p>
            )}
            
            <div>
              {isMobile || prefersReducedMotion ? (
                <motion.p
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: speed(5.2), duration: speed(1) }}
                  className="text-black inline-block relative"
                  style={{ fontFamily: 'Urbanist, sans-serif', fontSize: 'clamp(1.3rem, 3vw, 2.25rem)', fontWeight: '700', lineHeight: '1.3' }}
                >
                  <span className="relative z-10 px-2 py-1">
                    <span style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700' }}>Signet</span> helps you see<br className="md:hidden" />
                    {' '}what matters and why
                  </span>
                  <motion.span
                    initial={{ scaleX: 0 }}
                    animate={{ scaleX: 1 }}
                    transition={{ delay: speed(6.2), duration: speed(0.6), ease: "easeOut" }}
                    className="absolute inset-0"
                    style={{ transformOrigin: 'left', zIndex: 0, backgroundColor: 'rgba(168, 85, 247, 1)' }}
                  />
                </motion.p>
              ) : (
                <motion.p
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: speed(5.2), duration: speed(1) }}
                  className="text-black inline-block relative"
                  style={{ fontFamily: 'Urbanist, sans-serif', fontSize: 'clamp(1.3rem, 3vw, 2.25rem)', fontWeight: '700', lineHeight: '1.3' }}
                >
                  <span className="relative z-10 px-2 py-1">
                    <span style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700' }}>Signet</span> helps you see<br className="md:hidden" />
                    {' '}what matters and why
                  </span>
                  <motion.span
                    initial={{ scaleX: 0 }}
                    animate={{ scaleX: 1 }}
                    transition={{ delay: speed(6.2), duration: speed(0.6), ease: "easeOut" }}
                    className="absolute inset-0"
                    style={{ transformOrigin: 'left', zIndex: 0, backgroundColor: 'rgba(168, 85, 247, 1)' }}
                  />
                </motion.p>
              )}
            </div>
            
            <div>
              {isMobile || prefersReducedMotion ? (
                <motion.p
                  initial={{ opacity: 0, scale: 0.95 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ 
                    delay: speed(7.7), 
                    duration: speed(1), 
                    ease: [0.22, 1, 0.36, 1]
                  }}
                  className="text-black inline-block relative"
                  style={{ 
                    fontFamily: 'Urbanist, sans-serif',
                    fontSize: 'clamp(1.2rem, 2.8vw, 2rem)', 
                    fontWeight: '700',
                    fontStyle: 'italic',
                    letterSpacing: '0.02em'
                  }}
                >
                  <span className="relative z-10 px-2 py-1">With receipts</span>
                  <motion.span
                    initial={{ scaleX: 0 }}
                    animate={{ scaleX: 1 }}
                    transition={{ delay: speed(8.2), duration: speed(0.6), ease: "easeOut" }}
                    className="absolute inset-0"
                    style={{ transformOrigin: 'left', zIndex: 0, backgroundColor: 'rgba(168, 85, 247, 1)' }}
                  />
                </motion.p>
              ) : (
                <p
                  className="text-black inline-block relative"
                  style={{ 
                    fontFamily: 'Urbanist, sans-serif',
                    fontSize: 'clamp(1.2rem, 2.8vw, 2rem)', 
                    fontWeight: '700',
                    fontStyle: 'italic',
                    letterSpacing: '0.02em'
                  }}
                >
                  <span className="relative z-10 px-2 py-1">
                    {"With receipts".split("").map((char, index) => (
                      <motion.span
                        key={index}
                        initial={{ opacity: 0 }}
                        animate={{ opacity: 1 }}
                        transition={{ delay: speed(7.7 + (index * 0.05)), duration: speed(0.1) }}
                      >
                        {char}
                      </motion.span>
                    ))}
                  </span>
                  <motion.span
                    initial={{ scaleX: 0 }}
                    animate={{ scaleX: 1 }}
                    transition={{ delay: speed(8.35), duration: speed(0.6), ease: "easeOut" }}
                    className="absolute inset-0"
                    style={{ transformOrigin: 'left', zIndex: 0, backgroundColor: 'rgba(168, 85, 247, 1)' }}
                  />
                </p>
              )}
            </div>
          </div>
        </div>
        
        {/* Scan line effect - only on desktop */}
        {!isMobile && !prefersReducedMotion && (
          <motion.div
            initial={{ y: '-100%', opacity: 0.8 }}
            animate={{ y: '200%', opacity: 0 }}
            transition={{
              duration: speed(3),
              delay: speed(0.5),
              ease: "easeInOut"
            }}
            className="absolute inset-x-0 h-32 bg-gradient-to-b from-transparent via-white/10 to-transparent pointer-events-none"
          />
        )}
      </div>

      {/* The Problem Section */}
      <section className="py-32 px-6 bg-white border-t border-gray-200">
        <div className="max-w-6xl mx-auto">
          <div className="grid lg:grid-cols-2 gap-16">
            <div>
              <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '600', fontSize: '32px' }} className="text-black mb-6">
                Signal vs. Noise
              </h2>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '18px', lineHeight: '1.7' }} className="text-gray-700">
                Feeds are flooded with ragebait, AI slop, and brainrot designed to maximize engagement (and advertising revenue)—not quality. Oftentimes, the most helpful comment sits buried 7 levels deep in nested replies. Great contributors get overshadowed by 5-minute-old spambot accounts that bought 10k followers and posted provocative pics. Valuable perspectives drown in noise while nonsense posted by clout-chasing influencers goes viral. You waste hours scrolling through sludge or miss what actually matters.
              </p>
            </div>
            <div className="flex items-center">
              <div className="border-l-4 border-black pl-8">
                <p style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '28px', lineHeight: '1.4' }} className="text-black">
                  Quality content exists but<br />it's way too easy to miss
                </p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* What Signet Does */}
      <section id="what-signet-does" className="py-32 px-6 bg-black text-white">
        <div className="max-w-5xl mx-auto">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '48px' }} className="text-white mb-3">
            <span style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', letterSpacing: '-0.025em' }}>Signet</span> Is An App That Highlights What Matters
          </h2>
          <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '20px' }} className="text-gray-400 mb-12">
            We're using a combination of AI and human judgement to help separate signal from noise
          </p>
          <div className="grid md:grid-cols-2 gap-12 mb-16">
            <div className="bg-white/5 p-8 border border-white/10">
              <div className="w-12 h-12 mb-6" style={{ backgroundColor: 'rgba(255, 255, 0, 1)' }}></div>
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '20px' }} className="text-white mb-4">
                Convergent Patterns
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px', lineHeight: '1.6' }} className="text-gray-300">
                Multiple signals suggesting high value. When contributors have demonstrated sustained significant competence and proficiency, and community references align, we highlight it in yellow.
              </p>
            </div>
            <div className="bg-white/5 p-8 border border-white/10">
              <div className="w-12 h-12 mb-6" style={{ backgroundColor: 'rgba(168, 85, 247, 1)' }}></div>
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '20px' }} className="text-white mb-4">
                Divergent Perspectives
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px', lineHeight: '1.6' }} className="text-gray-300">
                Novel viewpoints worth considering. Quality minority positions that challenge consensus, highlighted in purple to prevent echo chambers.
              </p>
            </div>
          </div>
          <div className="flex flex-wrap gap-6">
            <a 
              href="mailto:info@signet.ing" 
              style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '600' }}
              className="px-10 py-4 bg-white text-black hover:bg-gray-200 transition-colors"
            >
              Contact Us
            </a>
            <a 
              href="#how-it-works" 
              style={{ fontFamily: 'Inter, sans-serif', fontWeight: '500' }}
              className="px-10 py-4 border-2 border-white text-white hover:bg-white hover:text-black transition-colors"
            >
              Learn More
            </a>
          </div>
        </div>
      </section>

      {/* Demo Section */}
      <section className="py-32 px-6 bg-gray-50">
        <div className="max-w-6xl mx-auto">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '48px' }} className="text-black mb-6 text-center">
            See for yourself
          </h2>
          <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '18px' }} className="text-gray-600 text-center mb-16 max-w-2xl mx-auto">
            Every highlight explains itself with receipts. No mysterious algorithms.
          </p>
          
          <DemoThread />
        </div>
      </section>

      {/* How Signet Works Section */}
      <section id="how-it-works" className="py-32 px-6 bg-white">
        <div className="max-w-5xl mx-auto">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '48px' }} className="text-black mb-16">
            How <span style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', letterSpacing: '-0.025em' }}>Signet</span> Works
          </h2>
          
          <div className="grid md:grid-cols-2 gap-16">
            <div>
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '20px' }} className="text-black mb-4">
                Foundation
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px', lineHeight: '1.7' }} className="text-gray-700">
                Like ancient signet rings that proved authorship by unforgeably stamping wax seals on documents, digital signatures allow for persistently verifiable identity online. We're building Signet on top of an <a href="https://nostr.com" target="_blank" rel="noopener noreferrer" className="text-purple-600 underline decoration-purple-400 underline-offset-2">open protocol</a> with millions of existing users that allows us to verify who's said what network-wide. When someone's been continuously helpful on a topic throughout their posting history, those contributions carry their unique digital "stamp"—the same identity over time. No sockpuppets claiming instant expertise. No corporate platform employees who could silently manipulate what it seems you say (or see). For the first time, a mix of AI and human judgement at scale can analyze contribution patterns that actually mean something because identity persists.
              </p>
            </div>
            
            <div>
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '20px' }} className="text-black mb-4">
                Faking is cheap, fact-checking is costly
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px', lineHeight: '1.7' }} className="text-gray-700 mb-4">
                We detect what matters:
              </p>
              <ul style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px', lineHeight: '1.7' }} className="text-gray-700 space-y-2 pl-6">
                <li className="relative before:content-['•'] before:absolute before:-left-4"><strong>Original Thinking</strong> (ideas others build upon)</li>
                <li className="relative before:content-['•'] before:absolute before:-left-4"><strong>Good Questions</strong> (that unlock discussions)</li>
                <li className="relative before:content-['•'] before:absolute before:-left-4"><strong>Consistent Presence</strong> (sustained quality over time)</li>
                <li className="relative before:content-['•'] before:absolute before:-left-4"><strong>Intellectual Honesty</strong> (admitting errors publicly)</li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* What Makes Signet Different */}
      <section className="py-32 px-6 bg-gray-50 border-t border-gray-200">
        <div className="max-w-5xl mx-auto">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '48px' }} className="text-black mb-4">
            What Makes <span style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', letterSpacing: '-0.025em' }}>Signet</span> Different
          </h2>
          <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '18px' }} className="text-gray-600 mb-16">
            We’re not another engagement‑maximization machine.
          </p>
          
          <div className="grid md:grid-cols-3 gap-8">
            <div className="bg-white p-8 border border-gray-200">
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '18px' }} className="text-black mb-3">
                Highlighting
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-700">
                We make quality visible wherever it's buried, not just reorder lists
              </p>
            </div>
            <div className="bg-white p-8 border border-gray-200">
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '18px' }} className="text-black mb-3">
                Dual perspectives
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-700">
                Yellow convergent AND purple divergent patterns prevent echo chambers
              </p>
            </div>
            <div className="bg-white p-8 border border-gray-200">
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '18px' }} className="text-black mb-3">
                Complete transparency
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-700">
                Receipts explain every highlight—no mysterious algorithms
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Comparison Table */}
      <section className="py-32 px-6 bg-white">
        <div className="max-w-6xl mx-auto">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '48px' }} className="text-black mb-16 text-center">
            Divergent Approaches
          </h2>
          
          <div className="grid lg:grid-cols-2 gap-8">
            <div className="border-2 border-gray-300 p-8">
              <h3 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '600', fontSize: '24px' }} className="text-gray-900 mb-8">
                Legacy Platforms
              </h3>
              <ul className="space-y-4">
                {[
                  'Addictive engagement model',
                  'Opaque algorithmic control',
                  'Corporate data control',
                  'Surveillance-driven profits',
                  'You are the product being sold'
                ].map((item, i) => (
                  <li key={i} className="flex items-start gap-3">
                    <span className="text-red-500 text-xl">×</span>
                    <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px' }} className="text-gray-700">{item}</span>
                  </li>
                ))}
              </ul>
            </div>
            
            <div className="border-2 border-black p-8 bg-black text-white">
              <h3 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '600', fontSize: '24px', letterSpacing: '-0.025em' }} className="text-white mb-8">
                Signet
              </h3>
              <ul className="space-y-4">
                {[
                  'Relevance & usefulness prioritized',
                  'Transparent, auditable algorithms',
                  'User-controlled data & networks',
                  'Open-source & community-driven',
                  'You own your digital experience'
                ].map((item, i) => (
                  <li key={i} className="flex items-start gap-3">
                    <span className="text-green-400 text-xl">✓</span>
                    <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px' }} className="text-gray-100">{item}</span>
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* Data & Limitations */}
      <section className="py-32 px-6 bg-gray-50">
        <div className="max-w-5xl mx-auto">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '48px' }} className="text-black mb-16">
            Data Scope & Limitations
          </h2>
          
          <div className="space-y-12">
            <div className="bg-white p-8 border border-gray-200">
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '20px' }} className="text-black mb-4">
                What we analyze
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px', lineHeight: '1.7' }} className="text-gray-700">
                Public messages from <a href="https://nostr.com" target="_blank" rel="noopener noreferrer" className="text-purple-600 underline decoration-purple-400 underline-offset-2">open protocols</a> with digital signatures. Network relationships. Engagement patterns. No external sites. No private data. No popularity metrics. We analyze contribution patterns, not claimed credentials.
              </p>
            </div>
            
            <div className="bg-white p-8 border border-gray-200">
              <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '20px' }} className="text-black mb-4">
                Honest limits
              </h3>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px', lineHeight: '1.7' }} className="text-gray-700">
                Patterns suggest potentially valuable contributions—they don't determine truth. Quality contributors can be wrong. New voices lack patterns. Sold accounts show behavioral changes. Receipts explain detected patterns; <em style={{ fontWeight: '700' }}>you</em> interpret meaning.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Tech & Open Source */}
      <section className="py-32 px-6 bg-black text-white">
        <div className="max-w-5xl mx-auto">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '48px' }} className="text-white mb-16">
            The Tech & Open Source
          </h2>
          
          <div className="grid md:grid-cols-2 gap-12">
            <div>
              <div className="mb-4 text-gray-400" style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '14px', letterSpacing: '0.1em', textTransform: 'uppercase' }}>
                Technology
              </div>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '18px', lineHeight: '1.7' }} className="text-gray-100">
                GPU-accelerated ML and graph analysis techniques (using cuGraph) process millions of contributions, identifying convergent/divergent patterns at scale.
              </p>
            </div>
            
            <div>
              <div className="mb-4 text-gray-400" style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '14px', letterSpacing: '0.1em', textTransform: 'uppercase' }}>
                Open Source
              </div>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '18px', lineHeight: '1.7' }} className="text-gray-100 mb-4">
                All code will be made public at
              </p>
              <a 
                href="https://github.com/signeting" 
                style={{ fontFamily: 'JetBrains Mono, monospace', fontWeight: '400', fontSize: '16px' }}
                className="text-yellow-300 hover:text-yellow-200 underline"
              >
                github.com/signeting
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="py-32 px-6 bg-white">
        <div className="max-w-4xl mx-auto">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '48px' }} className="text-black mb-16">
            FAQ
          </h2>
          
          <div className="space-y-8">
            {[
              {
                q: "How is this different from upvotes/likes/reposts/etc?",
                a: "Traditional platforms reward perceived popularity, which can easily be bought. We detect patterns that are difficult to fake—years of quality contributions can't be fabricated retroactively."
              },
              {
                q: "What about echo chambers?",
                a: "Dual highlighting prevents this. Yellow shows convergent value, purple shows divergent perspectives. You see both reinforcement AND challenges."
              },
              {
                q: "Can this be gamed?",
                a: "Gaming individual signals? Easy. Gaming all patterns comprehensively for years? That's just... actually being valuable."
              },
              {
                q: "What if accounts change hands?",
                a: "Behavioral patterns shift when accounts are sold. Receipts show recent vs. historical patterns—sudden changes are obvious."
              },
              {
                q: "Do you determine truth?",
                a: "No. We highlight patterns suggesting potential value. Smart people can be wrong. Receipts show our reasoning; you judge validity."
              },
              {
                q: "Why should non-technical people care?",
                a: "Every decision—health, money, careers—could be influenced by online discussions where quality is essentially invisible. We make the valuable stuff you're missing actually visible."
              },
              {
                q: "What exactly gets highlighted?",
                a: "It depends on the context, but about 15% yellow (convergent valuable), and 10% purple (divergent valuable). The rest stays unhighlighted. By default we hide obvious spam."
              }
            ].map((faq, i) => (
              <div key={i} className="border-b border-gray-200 pb-8 last:border-0">
                <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '18px' }} className="text-black mb-3">
                  {faq.q}
                </p>
                <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '16px', lineHeight: '1.7' }} className="text-gray-700">
                  {faq.a}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Final CTA */}
      <section className="py-40 px-6 bg-gradient-to-b from-black to-gray-900 text-white">
        <div className="max-w-4xl mx-auto text-center">
          <h2 style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '56px' }} className="text-white mb-6">
            Ready to see what<br className="hidden md:block" />
            {' '}you've been missing?
          </h2>
          <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '20px' }} className="text-gray-300 mb-12">
            Ask for early access. See for yourself.
          </p>
          
          <a 
            href="mailto:info@signet.ing" 
            style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '600', fontSize: '18px' }}
            className="inline-block px-12 py-5 bg-white text-black hover:bg-gray-100 transition-colors"
          >
            Contact Us
          </a>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-12 px-6 bg-black border-t border-gray-800">
        <div className="max-w-6xl mx-auto">
          <div className="flex flex-col md:flex-row justify-between items-center gap-4">
            <p style={{ fontFamily: 'Urbanist, sans-serif', fontWeight: '700', fontSize: '24px', letterSpacing: '-0.025em' }} className="text-white">
              Signet
            </p>
            <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '14px' }} className="text-gray-500">
              2025 Signet
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
