//! Normalized PCM conversion at the final device boundary.
//! Integer PCM uses a power-of-two scale, round-to-nearest and saturation.
//! Dither is only needed when samples actually fall between integer codes.

pub(crate) struct TpdfDither(u64);

impl TpdfDither {
    pub(crate) fn new(seed: u64) -> Self {
        Self(seed)
    }
    fn unit(&mut self) -> f64 {
        self.0 = self
            .0
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        (self.0 >> 11) as f64 / (1u64 << 53) as f64
    }
    fn quantize(&mut self, sample: f64, bits: u32, enabled: bool) -> f64 {
        let scale = (1u64 << (bits - 1)) as f64;
        let mut code = finite_sample(sample).clamp(-1.0, 1.0) * scale;
        // Exact PCM codes (including digital silence) need no requantization.
        if enabled && code.fract() != 0.0 {
            code += self.unit() - self.unit();
        }
        code.round().clamp(-scale, scale - 1.0)
    }
}

pub(crate) fn finite_sample(sample: f64) -> f64 {
    if sample.is_finite() {
        sample
    } else {
        0.0
    }
}

pub(crate) trait OutputSample: Copy {
    const SILENCE: Self;
    fn encode(sample: f64, dither: &mut TpdfDither, enabled: bool) -> Self;
}
macro_rules! signed {
    ($ty:ty, $bits:expr) => {
        impl OutputSample for $ty {
            const SILENCE: Self = 0;
            fn encode(sample: f64, dither: &mut TpdfDither, enabled: bool) -> Self {
                dither.quantize(sample, $bits, enabled) as Self
            }
        }
    };
}
macro_rules! unsigned {
    ($ty:ty, $bits:expr) => {
        impl OutputSample for $ty {
            const SILENCE: Self = 1 << ($bits - 1);
            fn encode(sample: f64, dither: &mut TpdfDither, enabled: bool) -> Self {
                (dither.quantize(sample, $bits, enabled) + (1u64 << ($bits - 1)) as f64) as Self
            }
        }
    };
}
signed!(i8, 8);
signed!(i16, 16);
signed!(i32, 32);
unsigned!(u8, 8);
unsigned!(u16, 16);
unsigned!(u32, 32);
impl OutputSample for f32 {
    const SILENCE: Self = 0.0;
    fn encode(sample: f64, _: &mut TpdfDither, _: bool) -> Self {
        finite_sample(sample).clamp(-(f32::MAX as f64), f32::MAX as f64) as Self
    }
}
impl OutputSample for f64 {
    const SILENCE: Self = 0.0;
    fn encode(sample: f64, _: &mut TpdfDither, _: bool) -> Self {
        finite_sample(sample)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn all_i16_codes_round_trip_with_dither_enabled() {
        let mut noise = TpdfDither::new(123);
        for n in i16::MIN..=i16::MAX {
            assert_eq!(i16::encode(n as f64 / 32768.0, &mut noise, true), n);
        }
    }
    #[test]
    fn i32_lsb_and_extremes_survive() {
        let mut noise = TpdfDither::new(123);
        for n in [
            i32::MIN,
            i32::MIN + 1,
            -16777217,
            -1,
            0,
            1,
            16777217,
            i32::MAX - 1,
            i32::MAX,
        ] {
            assert_eq!(i32::encode(n as f64 / 2147483648.0, &mut noise, true), n);
        }
    }
    #[test]
    fn unsigned_zero_is_midpoint_and_endpoints_are_correct() {
        let mut noise = TpdfDither::new(123);
        for n in 0..=u16::MAX {
            assert_eq!(
                u16::encode((n as f64 - 32768.0) / 32768.0, &mut noise, true),
                n
            );
        }
        assert_eq!(u8::encode(0.0, &mut noise, true), 128);
        assert_eq!(u16::SILENCE, 32768);
        assert_eq!(u8::SILENCE, 128);
    }
    #[test]
    fn rounding_is_symmetric_and_nonfinite_input_is_silent() {
        let mut noise = TpdfDither::new(123);
        assert_eq!(i16::encode(0.75 / 32768.0, &mut noise, false), 1);
        assert_eq!(i16::encode(-0.75 / 32768.0, &mut noise, false), -1);
        assert_eq!(i16::encode(2.0, &mut noise, false), i16::MAX);
        assert_eq!(i16::encode(-2.0, &mut noise, false), i16::MIN);
        assert_eq!(f32::encode(f64::NAN, &mut noise, true), 0.0);
        assert_eq!(u16::encode(f64::INFINITY, &mut noise, true), u16::SILENCE);
    }
}
