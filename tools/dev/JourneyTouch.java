import android.os.SystemClock;
import android.view.InputDevice;
import android.view.InputEvent;
import android.view.MotionEvent;
import java.lang.reflect.Method;

/** Shell-side OS multitouch input, using coordinates from the live scene inspector. */
public final class JourneyTouch {
    private static Object manager;
    private static Method inject;
    private static long downTime;

    private static void send(int action, int count, float[] xy) throws Exception {
        MotionEvent.PointerProperties[] properties = new MotionEvent.PointerProperties[count];
        MotionEvent.PointerCoords[] coords = new MotionEvent.PointerCoords[count];
        for (int i = 0; i < count; i++) {
            properties[i] = new MotionEvent.PointerProperties();
            properties[i].id = i;
            properties[i].toolType = MotionEvent.TOOL_TYPE_FINGER;
            coords[i] = new MotionEvent.PointerCoords();
            coords[i].x = xy[i * 2];
            coords[i].y = xy[i * 2 + 1];
            coords[i].pressure = 1;
            coords[i].size = 0.1f;
        }
        MotionEvent event = MotionEvent.obtain(downTime, SystemClock.uptimeMillis(), action, count,
                properties, coords, 0, 0, 1, 1, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0);
        try {
            if (!Boolean.TRUE.equals(inject.invoke(manager, event, 2))) {
                throw new IllegalStateException("OS rejected multitouch input");
            }
        } finally {
            event.recycle();
        }
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 9) throw new IllegalArgumentException("Expected 8 coordinates and duration");
        float[] start = new float[4];
        float[] end = new float[4];
        for (int i = 0; i < 4; i++) {
            start[i] = Float.parseFloat(args[i]);
            end[i] = Float.parseFloat(args[i + 4]);
        }
        int duration = Integer.parseInt(args[8]);
        if (duration < 100 || duration > 2000) throw new IllegalArgumentException("Duration outside 100..2000 ms");
        Class<?> type = Class.forName("android.hardware.input.InputManagerGlobal");
        manager = type.getMethod("getInstance").invoke(null);
        inject = type.getMethod("injectInputEvent", InputEvent.class, int.class);
        downTime = SystemClock.uptimeMillis();
        float[] current = start.clone();
        boolean finished = false;
        try {
            send(MotionEvent.ACTION_DOWN, 1, current);
            SystemClock.sleep(20);
            send(MotionEvent.ACTION_POINTER_DOWN | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2, current);
            long begin = SystemClock.uptimeMillis();
            for (int frame = 1; frame <= 30; frame++) {
                SystemClock.sleep(Math.max(0, begin + duration * frame / 30 - SystemClock.uptimeMillis()));
                for (int i = 0; i < 4; i++) current[i] = start[i] + (end[i] - start[i]) * frame / 30f;
                send(MotionEvent.ACTION_MOVE, 2, current);
            }
            send(MotionEvent.ACTION_POINTER_UP | (1 << MotionEvent.ACTION_POINTER_INDEX_SHIFT), 2, current);
            SystemClock.sleep(25);
            send(MotionEvent.ACTION_UP, 1, current);
            finished = true;
            System.out.println("MULTITOUCH_COMPLETE");
        } finally {
            if (!finished) send(MotionEvent.ACTION_CANCEL, 2, current);
        }
    }
}
