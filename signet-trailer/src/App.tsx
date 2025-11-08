import { motion } from 'motion/react';
import { useState, useEffect } from 'react';

export default function App() {
  const letters = "UNBREAK".split("");
  const [showFlash, setShowFlash] = useState(false);
  
  useEffect(() => {
    const timer = setTimeout(() => {
      setShowFlash(true);
      setTimeout(() => setShowFlash(false), 200);
    }, 1600);
    return () => clearTimeout(timer);
  }, []);
  
  return (
    <div className="min-h-screen bg-black flex items-center justify-center overflow-hidden relative">
      {/* Background animated gradient */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: 0.2 }}
        transition={{ duration: 2 }}
        className="absolute inset-0 bg-gradient-to-br from-purple-900 via-violet-900 to-black"
      />
      
      {/* Radial glow effect */}
      <motion.div
        initial={{ scale: 0, opacity: 0 }}
        animate={{ scale: 2, opacity: 0.15 }}
        transition={{ duration: 2, delay: 0.5 }}
        className="absolute inset-0 flex items-center justify-center"
      >
        <div className="w-[600px] h-[600px] rounded-full bg-purple-600 blur-[150px]" />
      </motion.div>
      
      {/* Flash effect */}
      <motion.div
        initial={{ opacity: 0 }}
        animate={{ opacity: showFlash ? 1 : 0 }}
        className="absolute inset-0 bg-white pointer-events-none"
        transition={{ duration: 0.1 }}
      />
      
      <div className="text-center px-4 relative z-10">
        <div className="flex justify-center items-center flex-wrap gap-1">
          {letters.map((letter, index) => (
            <motion.span
              key={index}
              initial={{
                x: (Math.random() - 0.5) * 1200,
                y: (Math.random() - 0.5) * 900,
                rotate: (Math.random() - 0.5) * 1080,
                opacity: 0,
                scale: 0.1,
                filter: 'blur(20px)'
              }}
              animate={{
                x: 0,
                y: 0,
                rotate: 0,
                opacity: 1,
                scale: 1,
                filter: [
                  'blur(20px)',
                  'blur(8px)',
                  'blur(2px)',
                  'blur(0px)',
                  'blur(0px) drop-shadow(12px 0 0 rgba(255,0,0,1)) drop-shadow(-12px 0 0 rgba(0,255,255,1))',
                  'blur(0px) drop-shadow(15px 2px 0 rgba(255,0,0,1)) drop-shadow(-15px -2px 0 rgba(0,255,255,1))',
                  'blur(0px) drop-shadow(10px 0 0 rgba(255,0,0,1)) drop-shadow(-10px 0 0 rgba(0,255,255,1))',
                  'blur(0px) drop-shadow(4px 0 0 rgba(255,0,0,0.6)) drop-shadow(-4px 0 0 rgba(0,255,255,0.6))',
                  'blur(0px)',
                  'blur(0px)'
                ]
              }}
              transition={{
                duration: 1.8,
                delay: index * 0.15,
                ease: [0.22, 1, 0.36, 1],
                filter: {
                  times: [0, 0.25, 0.5, 0.6, 0.65, 0.7, 0.75, 0.85, 0.95, 1],
                  duration: 1.8,
                  delay: index * 0.15
                }
              }}
              className="text-white inline-block"
              style={{
                fontSize: 'clamp(4rem, 15vw, 12rem)',
                fontWeight: '900',
                lineHeight: '1',
                textShadow: '0 0 60px rgba(168, 85, 247, 0.8), 0 0 120px rgba(147, 51, 234, 0.6)',
                letterSpacing: '-0.02em'
              }}
            >
              {letter}
            </motion.span>
          ))}
        </div>
        
        <motion.div
          initial={{ opacity: 0, y: 100, scale: 0.8, filter: 'blur(10px)' }}
          animate={{ opacity: 1, y: 0, scale: 1, filter: 'blur(0px)' }}
          transition={{
            duration: 1.5,
            delay: 1.8,
            ease: [0.22, 1, 0.36, 1]
          }}
          className="text-white"
          style={{
            fontSize: 'clamp(4rem, 15vw, 12rem)',
            fontWeight: '900',
            lineHeight: '1',
            textShadow: '0 0 60px rgba(168, 85, 247, 0.8), 0 0 120px rgba(147, 51, 234, 0.6)',
            letterSpacing: '-0.02em'
          }}
        >
          THE<br />INTERNET
        </motion.div>
        
        <motion.div
          initial={{ scaleX: 0 }}
          animate={{ scaleX: 1 }}
          transition={{ delay: 2.5, duration: 1.2, ease: "easeInOut" }}
          className="h-1 bg-gradient-to-r from-transparent via-purple-400 to-transparent mt-16 mb-12 mx-auto max-w-3xl"
        />
        
        <div className="max-w-4xl mx-auto space-y-6">
          <motion.p
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 3.2, duration: 1 }}
            className="text-purple-100/80"
            style={{ fontSize: 'clamp(1.1rem, 2.5vw, 1.75rem)', lineHeight: '1.4' }}
          >
            The internet has a credibility crisis<br className="sm:hidden" />{' '}
            and polarization problem
          </motion.p>
          
          <motion.p
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 5.2, duration: 1 }}
            className="text-white"
            style={{ fontSize: 'clamp(1.3rem, 3vw, 2.25rem)', fontWeight: '700', lineHeight: '1.3' }}
          >
            Signet helps you see<br className="sm:hidden" />{' '}
            what matters and why
          </motion.p>
          
          <motion.p
            initial={{ opacity: 0, scale: 0.95 }}
            animate={{ 
              opacity: 1, 
              scale: 1,
              textShadow: [
                '0 0 20px rgba(216, 180, 254, 0.6), 0 0 40px rgba(168, 85, 247, 0.4)',
                '0 0 30px rgba(216, 180, 254, 0.8), 0 0 60px rgba(168, 85, 247, 0.6)',
                '0 0 20px rgba(216, 180, 254, 0.6), 0 0 40px rgba(168, 85, 247, 0.4)',
              ]
            }}
            transition={{ 
              delay: 7.7, 
              duration: 1, 
              ease: [0.22, 1, 0.36, 1],
              textShadow: {
                delay: 8.4,
                duration: 2,
                repeat: Infinity,
                repeatType: "reverse",
                ease: "easeInOut"
              }
            }}
            className="text-purple-300"
            style={{ 
              fontSize: 'clamp(1.2rem, 2.8vw, 2rem)', 
              fontWeight: '600',
              fontStyle: 'italic',
              letterSpacing: '0.02em'
            }}
          >
            {"With receipts".split("").map((char, index) => (
              <motion.span
                key={index}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 7.7 + (index * 0.05), duration: 0.1 }}
              >
                {char}
              </motion.span>
            ))}
          </motion.p>
        </div>
      </div>
      
      {/* Scan line effect */}
      <motion.div
        initial={{ y: '-100%', opacity: 0.8 }}
        animate={{ y: '200%', opacity: 0 }}
        transition={{
          duration: 3,
          delay: 0.5,
          ease: "easeInOut"
        }}
        className="absolute inset-x-0 h-32 bg-gradient-to-b from-transparent via-white/10 to-transparent pointer-events-none"
      />
    </div>
  );
}