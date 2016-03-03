# Feb 2016, orthopteroid@gmail.com, MIT license.
# for julia 0.5.0-dev+2944 (e01b357)
# kudos to https://github.com/rennis250/SDL.jl

macro checked_lib(libname, path)
    ( Base.Libdl.dlopen_e(path) == C_NULL ) && error("Unable to load $libname ($path).")
    quote const $(esc(libname)) = $path end
end
@checked_lib libSDL "/usr/lib/x86_64-linux-gnu/libSDL-1.2.so.0"

type SDL_AudioSpec
        freq::Int32	
        format::UInt16
        channels::UInt8
        silence::UInt8
        samples::UInt16
        padding::UInt16
        size::UInt32
		callback::Ptr{Void}
        userdata::Ptr{Void}
end

# # # # # # # # # # # # # # # # # # # # # # # # # # # # 

# represents current phase angle and direction of sweep
type Oscillator
	theta::Cfloat
	step::Cfloat
end

Oscillator(freq::Real, sampledelta_1khz::Real) = Oscillator( Cfloat(0), Cfloat(freq * sampledelta_1khz) )

# step the oscillator to the next phase angle for the programmed frequency
@inline function step!(O::Oscillator)
	O.theta += O.step
	if O.theta < Cfloat(-1.57079) # pi / 2
		O.theta -= (O.theta - Cfloat(-1.57079))
		O.step = -O.step
	elseif O.theta > Cfloat(+1.57079)
		O.theta -= (O.theta - Cfloat(+1.57079))
		O.step = -O.step
	end
	return O
end

# given the oscillator's angle, return sin(angle)
@inline function signal(O::Oscillator)
	# only valid between -pi/2 and +pi/2
	const Cpi = Cfloat(3.14159)
	y = ((Cfloat(4.) / Cpi) * O.theta + (Cfloat(-4.) / (Cpi * Cpi)) * O.theta * abs( O.theta ))
	z = Cfloat(0.225) * (y * abs( y ) - y) + y
	return Cshort( round( z * 32765 ) )
end

# # # # # # # # # # # # # # # # # # # # # # # # # # # # 

const SAMPLES = 4096 * 1 # bigger buffer = less skipping
const SAMPLERATE = 22050
const SAMPLEDELTA_1KHZ = 2 * pi / SAMPLERATE

# lame attempt at double buffering
const buffer0 = zeros(Cshort, SAMPLES)
const buffer1 = zeros(Cshort, SAMPLES)
const bufbool = Array(Bool)

# this darn thing skips - I think julia is taking too long in this callpath
function mixerCallback(userdata::Ptr{Void}, stream::Ptr{Cshort}, len::Int32)
	rc = ccall((:SDL_MixAudio, libSDL), Int32, (Ptr{Cshort}, Ref{Cshort}, UInt32, Int32), stream, bufbool[] ? buffer1 : buffer0, len, 0x80) # SDL_MIX_MAXVOLUME
	return nothing
end
const mixerCallback_c = cfunction(mixerCallback, Void, (Ptr{Void}, Ptr{Cshort}, Int32))

asDesired = SDL_AudioSpec( SAMPLERATE, 0x9010, 1, 0, SAMPLES, 0, 0, mixerCallback_c, 0 ) # AUDIO_S16MSB
asCurrent = SDL_AudioSpec( 0, 0, 0, 0, 0, 0, 0, mixerCallback_c, 0 )

function main()
	global bufbool # hack: redeclare as a global
	bufbool[] = false

	rc = ccall((:SDL_Init, libSDL), Int32, (UInt32, ), 0x0001 | 0x0010 ) # SDL_INIT_TIMER | SDL_INIT_AUDIO
	rc = ccall((:SDL_OpenAudio, libSDL), Int32, (Ref{SDL_AudioSpec}, Ref{SDL_AudioSpec}), asDesired, asCurrent)
	rc = ccall((:SDL_PauseAudio, libSDL), Void, (UInt32, ), 0x00 ) # arg is pause_on
	
	osc = Oscillator( 440, SAMPLEDELTA_1KHZ )
	
	lasttick = ccall((:SDL_GetTicks, libSDL), UInt32, ()) + 1 * 500
	while ccall((:SDL_GetTicks, libSDL), UInt32, ()) <= lasttick
	
		# fill the buffer that is not playing
		if bufbool[] == false
			for i = 1:SAMPLES
				buffer1[ i ] = signal( step!( osc ) )
			end
		else
			for i = 1:SAMPLES
				buffer0[ i ] = signal( step!( osc ) )
			end
		end
		
		# swap playback and fill buffers
		rc = ccall((:SDL_LockAudio, libSDL), Void, ())
		bufbool[] = !bufbool[]
		rc = ccall((:SDL_UnlockAudio, libSDL), Void, ())
		
	end
	
	rc = ccall((:SDL_Quit, libSDL), Void, ())
	return 0
end
