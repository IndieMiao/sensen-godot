import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import java.lang.reflect.Method;

/** Shell-only touch fixture for the isolated emulator; no accessibility service or app install. */
public final class RoomTouch {
    static Object manager;
    static Method inject;
    static long down;
    static int eventCount;
    static void send(int action, float[] xy) throws Exception {
        int count = xy.length / 2;
        MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[count];
        MotionEvent.PointerCoords[] coords = new MotionEvent.PointerCoords[count];
        for (int i = 0; i < count; i++) {
            properties[i] = new MotionEvent.PointerProperties();
            properties[i].id = i;
            properties[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
            coords[i] = new MotionEvent.PointerCoords();
            coords[i].x = xy[2*i]; coords[i].y = xy[2*i+1];
            coords[i].pressure = 1; coords[i].size = .1f;
        }
        MotionEvent event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, count,
            properties, coords, 0, 0, 1, 1, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0);
        if (!Boolean.TRUE.equals(inject.invoke(manager, event, 2))) throw new IllegalStateException("Touch injection rejected");
        event.recycle();
        eventCount++;
    }
    public static void main(String[] args) throws Exception {
        Class<?> clazz;
        try { clazz = Class.forName("android.hardware.input.InputManagerGlobal"); }
        catch (ClassNotFoundException e) { clazz = Class.forName("android.hardware.input.InputManager"); }
        manager = clazz.getDeclaredMethod("getInstance").invoke(null);
        inject = clazz.getMethod("injectInputEvent", InputEvent.class, int.class);
        down = SystemClock.uptimeMillis();
        if (args[0].equals("drag")) {
            float sx=Float.parseFloat(args[1]), sy=Float.parseFloat(args[2]);
            float ex=Float.parseFloat(args[3]), ey=Float.parseFloat(args[4]);
            long movement=Long.parseLong(args[5]), hold=Long.parseLong(args[6]);
            send(MotionEvent.ACTION_DOWN, new float[]{sx,sy});
            long start=SystemClock.uptimeMillis();
            while (SystemClock.uptimeMillis()-start < movement+hold) {
                float t=Math.min(1,(SystemClock.uptimeMillis()-start)/(float)Math.max(1,movement));
                send(MotionEvent.ACTION_MOVE,new float[]{sx+(ex-sx)*t,sy+(ey-sy)*t});
                Thread.sleep(16);
            }
            send(MotionEvent.ACTION_UP,new float[]{ex,ey});
        } else if (args[0].equals("pinch")) {
            float cx=Float.parseFloat(args[1]), cy=Float.parseFloat(args[2]);
            float from=Float.parseFloat(args[3]), to=Float.parseFloat(args[4]);
            long duration=Long.parseLong(args[5]);
            send(MotionEvent.ACTION_DOWN,new float[]{cx-from/2,cy});
            send(MotionEvent.ACTION_POINTER_DOWN+(1<<8),new float[]{cx-from/2,cy,cx+from/2,cy});
            long start=SystemClock.uptimeMillis();
            while (SystemClock.uptimeMillis()-start < duration) {
                float t=(SystemClock.uptimeMillis()-start)/(float)duration;
                float radius=(from+(to-from)*t)/2;
                send(MotionEvent.ACTION_MOVE,new float[]{cx-radius,cy,cx+radius,cy});
                Thread.sleep(16);
            }
            send(MotionEvent.ACTION_POINTER_UP+(1<<8),new float[]{cx-to/2,cy,cx+to/2,cy});
            send(MotionEvent.ACTION_UP,new float[]{cx-to/2,cy});
        } else throw new IllegalArgumentException("Expected drag or pinch");
        System.out.println("Injected " + eventCount + " events over " + (SystemClock.uptimeMillis()-down) + "ms");
    }
}
