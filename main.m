#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <VideoToolbox/VideoToolbox.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <netinet/tcp.h>
#import <arpa/inet.h>

// Khai báo thủ công thay vì import <IOSurface/IOSurface.h> vì SDK 14.5 không có
typedef struct __IOSurface *IOSurfaceRef;
extern IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
extern void CFRelease(CFTypeRef cf);
extern IOSurfaceRef CARenderServerRenderDisplay(int display, CFStringRef name, IOSurfaceRef surface);
extern const CFStringRef kIOSurfaceWidth;
extern const CFStringRef kIOSurfaceHeight;
extern const CFStringRef kIOSurfaceBytesPerElement;
extern const CFStringRef kIOSurfacePixelFormat;

static VTCompressionSessionRef compressionSession = NULL;
static int client_socket = -1;

// Hàm callback sau khi mã hóa xong 1 frame
void didEncodeFrame(void *outputCallbackRefCon, void *sourceFrameRefCon, OSStatus status, VTEncodeInfoFlags infoFlags, CMSampleBufferRef sampleBuffer) {
    if (status != noErr || !sampleBuffer) return;
    if (client_socket < 0) return;

    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length;
    char *dataPointer;
    CMBlockBufferGetDataPointer(dataBuffer, 0, NULL, &length, &dataPointer);

    uint32_t frameLength = (uint32_t)length;
    send(client_socket, &frameLength, sizeof(frameLength), 0);
    send(client_socket, dataPointer, length, 0);
}

void setupEncoder(int width, int height) {
    VTCompressionSessionCreate(NULL, width, height, kCMVideoCodecType_H264, NULL, NULL, NULL, didEncodeFrame, NULL, &compressionSession);
    VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);
    VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
    
    int bitrate = 4000000;
    CFNumberRef bitrateRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &bitrate);
    VTSessionSetProperty(compressionSession, kVTCompressionPropertyKey_AverageBitRate, bitrateRef);
    CFRelease(bitrateRef);
    VTCompressionSessionPrepareToEncodeFrames(compressionSession);
}

int main(int argc, char * argv[]) {
    @autoreleasepool {
        NSLog(@"Starting iosstream daemon...");

        int server_socket = socket(AF_INET, SOCK_STREAM, 0);
        int opt = 1;
        setsockopt(server_socket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        int flag = 1;
        setsockopt(server_socket, IPPROTO_TCP, TCP_NODELAY, (char *) &flag, sizeof(int));

        struct sockaddr_in server_addr;
        server_addr.sin_family = AF_INET;
        server_addr.sin_addr.s_addr = INADDR_ANY;
        server_addr.sin_port = htons(27183);

        bind(server_socket, (struct sockaddr *)&server_addr, sizeof(server_addr));
        listen(server_socket, 1);
        NSLog(@"Listening on port 27183. Waiting for PC connection...");

        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        client_socket = accept(server_socket, (struct sockaddr *)&client_addr, &client_len);
        NSLog(@"PC connected! Starting screen capture...");

        UIScreen *mainScreen = [UIScreen mainScreen];
        CGRect bounds = mainScreen.bounds;
        CGFloat scale = mainScreen.scale;
        int width = bounds.size.width * scale;
        int height = bounds.size.height * scale;

        setupEncoder(width, height);

        while (1) {
            CFDictionaryRef dict = (__bridge CFDictionaryRef)@{
                (__bridge NSString *)kIOSurfaceWidth: @(width),
                (__bridge NSString *)kIOSurfaceHeight: @(height),
                (__bridge NSString *)kIOSurfaceBytesPerElement: @4,
                (__bridge NSString *)kIOSurfacePixelFormat: @(kCVPixelFormatType_32BGRA)
            };
            
            IOSurfaceRef surface = IOSurfaceCreate(dict);
            CARenderServerRenderDisplay(0, CFSTR("LCD"), surface);

            CVPixelBufferRef pixelBuffer = NULL;
            CVPixelBufferCreateWithIOSurface(NULL, surface, NULL, &pixelBuffer);

            CMTime pts = CMTimeMakeWithSeconds(CACurrentMediaTime(), 1000000);
            VTCompressionSessionEncodeFrame(compressionSession, pixelBuffer, pts, kCMTimeInvalid, NULL, NULL, NULL);

            CVPixelBufferRelease(pixelBuffer);
            CFRelease(surface);

            [NSThread sleepForTimeInterval:0.016];
        }
    }
    return 0;
}s
