class_name Math


static func gcd(a: int, b: int) -> int:
	if b > a:
		return gcd(b, a)
	
	if a == 0 or b == 0:
		return a
	
	return gcd(b, a % b)
