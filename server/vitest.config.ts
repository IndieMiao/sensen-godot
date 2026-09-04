import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // DB 套件共用同一个 TEST_DATABASE_URL，每个文件开头都 truncateAll。并行跑时
    // 两个文件会互相清空对方的数据——2026-09-04 加第二个 DB 文件时立刻炸出来，
    // 而且单跑任一文件都是绿的，非常难查。串行执行的代价只有几秒。
    fileParallelism: false,
  },
});
