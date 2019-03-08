include Math

# Random number generator for triangular distribution
def trirng(m, low, high)
  return nil unless high > low && m > low && m < high
  u = rand
  if u <= (m-low)/(high-low)
    r = low+ Math.sqrt(u*(high-low)*(m-low))
  else
    r = high - Math.sqrt((1.0-u)*(high-low)*(high-m))
  end
  return r
end
