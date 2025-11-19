export default function DemoThread() {
  return (
    <div className="bg-white border border-gray-300 shadow-lg overflow-hidden">
      {/* Original Post */}
      <div className="p-6 bg-gray-50 border-b border-gray-300">
        <div className="flex gap-3">
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-2">
              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/healthseeker42</span>
              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• posted 2 hours ago</span>
            </div>
            <h3 style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '18px' }} className="text-black">
              What's the healthiest diet for longevity?
            </h3>
          </div>
        </div>
      </div>
      
      {/* Comments */}
      <div className="p-6 space-y-6">
        {/* Comment 1 */}
        <div className="flex gap-3">
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-2">
              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/mediterr_fan</span>
              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• 1 hour ago</span>
            </div>
            <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-800">
              Mediterranean diet obviously
            </p>
            
            {/* Nested Reply */}
            <div className="ml-6 mt-4 pl-4 border-l-2 border-gray-200">
              <div className="flex gap-3">
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-2">
                    <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/casual_agrees</span>
                    <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• 58 minutes ago</span>
                  </div>
                  <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-800">
                    This is the way
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Comment 2 with nested quality content */}
        <div className="flex gap-3">
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-2">
              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/health_basics</span>
              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• 1 hour ago</span>
            </div>
            <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-800">
              Just eat less processed food
            </p>
            
            {/* Nested replies */}
            <div className="ml-6 mt-4 pl-4 border-l-2 border-gray-200 space-y-4">
              <div className="flex gap-3">
                <div className="flex-1">
                  <div className="flex items-center gap-2 mb-2">
                    <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/agreed123</span>
                    <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• 52 minutes ago</span>
                  </div>
                  <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-800">
                    Exactly, common sense
                  </p>
                  
                  {/* HIGHLIGHTED EXPERT COMMENT */}
                  <div className="ml-6 mt-4 pl-4 border-l-2 border-gray-200">
                    <div className="p-5" style={{ backgroundColor: 'rgba(255, 255, 0, 1)' }}>
                      <div className="flex gap-3">
                        <div className="flex-1">
                          <div className="flex items-center gap-2 mb-2">
                            <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-black">u/RD_nutrition_science</span>
                            <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-700">• 38 minutes ago</span>
                          </div>
                          <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.7' }} className="text-black mb-3">
                            Registered dietitian here. The convergent evidence points to: mostly plants, whole foods, minimal processing, adequate protein (0.8-1g/lb), healthy fats. Specific diet framework matters less than these patterns. Blue zones all share these despite different cuisines. 
                            <br /><br />
                            But here's what not too many people ask: why do all "successful" diets work SHORT-term but seem to fail longer-term? The answer changes everything about how we should eat...
                          </p>
                          <div className="flex items-start gap-2 text-sm bg-black/5 p-3 rounded">
                            <span className="text-lg">🧾</span>
                            <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '13px', lineHeight: '1.6' }} className="text-black/80">
                              <strong>CONVERGENT</strong> - Participant in 50+ nutrition discussions with ~70% useful contributions, ~60% questions unlock valuable responses
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* HIGHLIGHTED DIVERGENT COMMENT - Vegan */}
        <div className="p-5" style={{ backgroundColor: 'rgba(168, 85, 247, 1)' }}>
          <div className="flex gap-3">
            <div className="flex-1">
              <div className="flex items-center gap-2 mb-2">
                <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-black">u/plant_based_decade</span>
                <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-800">• 45 minutes ago</span>
              </div>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.7' }} className="text-black mb-3">
                10-year vegan here. Everyone debates protein, but I noticed something interesting: populations with highest longevity eat plants differently than vegans. They ferment, sprout, and combine in ways that change bioavailability. Modern veganism might be missing ancient preparation wisdom. Adventist studies show the pattern but not the mechanism.
              </p>
              <div className="flex items-start gap-2 text-sm bg-black/5 p-3 rounded">
                <span className="text-lg">🧾</span>
                <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '13px', lineHeight: '1.6' }} className="text-black/80">
                  <strong>DIVERGENT</strong> - Participant in 300+ nutrition discussions with ~90% useful contributions from plant-based perspective, innovative concepts referenced 20+ times
                </p>
              </div>
            </div>
          </div>
        </div>

        {/* Reply to vegan comment */}
        <div className="ml-12 pl-4 border-l-2 border-gray-200 space-y-4">
          <div className="flex gap-3">
            <div className="flex-1">
              <div className="flex items-center gap-2 mb-2">
                <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/curious_q</span>
                <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• 32 minutes ago</span>
              </div>
              <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-800">
                But what about B12?
              </p>
              
              {/* HIGHLIGHTED DIVERGENT COUNTER-COMMENT - Carnivore */}
              <div className="ml-6 mt-4 pl-4 border-l-2 border-gray-200">
                <div className="p-5" style={{ backgroundColor: 'rgba(168, 85, 247, 1)' }}>
                  <div className="flex gap-3">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-2">
                        <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-black">u/ex_vegan_carnivore</span>
                        <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-800">• 24 minutes ago</span>
                      </div>
                      <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.7' }} className="text-black mb-3">
                        Ex-vegan, now carnivore 3 years. At first I thought my diet change had cured a bunch of issues I was having... but, I think I may have been wrong. Still have some autoimmune flares, just less frequent. Bloodwork improved but HDL could be better. What DID change: mental clarity and sustained energy. Not a miracle, but significant for me. Your results may vary.
                      </p>
                      <div className="flex items-start gap-2 text-sm bg-black/5 p-3 rounded">
                        <span className="text-lg">🧾</span>
                        <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '13px', lineHeight: '1.6' }} className="text-black/80">
                          <strong>DIVERGENT</strong> - Participant in 20+ nutrition discussions with ~70% useful contributions from carnivore perspective, intellectually honest 30+ times
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
                
                {/* Nested replies to carnivore comment */}
                <div className="ml-6 mt-4 pl-4 border-l-2 border-gray-200 space-y-4">
                  <div className="flex gap-3">
                    <div className="flex-1">
                      <div className="flex items-center gap-2 mb-2">
                        <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/shocked_reader</span>
                        <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• 18 minutes ago</span>
                      </div>
                      <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-800">
                        This is insane
                      </p>
                      
                      {/* Final nested reply */}
                      <div className="ml-6 mt-4 pl-4 border-l-2 border-gray-200">
                        <div className="flex gap-3">
                          <div className="flex-1">
                            <div className="flex items-center gap-2 mb-2">
                              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/peaceful_observer</span>
                              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• 12 minutes ago</span>
                            </div>
                            <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-800">
                              Let people eat what works for them
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Final low-quality comment */}
        <div className="flex gap-3">
          <div className="flex-1">
            <div className="flex items-center gap-2 mb-2">
              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '600', fontSize: '13px' }} className="text-gray-900">u/fitness_bro_2024</span>
              <span style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '12px' }} className="text-gray-500">• 5 minutes ago</span>
            </div>
            <p style={{ fontFamily: 'Inter, sans-serif', fontWeight: '400', fontSize: '15px', lineHeight: '1.6' }} className="text-gray-800">
              Calories in, calories out is all that matters bro
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}