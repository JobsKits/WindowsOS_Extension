// ProjectSetupProcess.cs | 当前任务的实时控制台进程与原始输出
// Created by Jobs on 2026年10月28日，星期三.
using System;
using System.IO;
using System.Text;
using System.Diagnostics;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Threading;
namespace Jobs {
 public sealed class SetupProcess : IDisposable {
  readonly Process process = new Process();
  readonly object gate = new object();
  readonly StringBuilder output = new StringBuilder();
  readonly StringBuilder errors = new StringBuilder();
  readonly ConcurrentQueue<string> lines = new ConcurrentQueue<string>();
  readonly string raw;
  readonly System.Threading.ManualResetEvent outDone = new System.Threading.ManualResetEvent(false);
  readonly System.Threading.ManualResetEvent errDone = new System.Threading.ManualResetEvent(false);
  public string OutputFailure { get; private set; }
  public SetupProcess(ProcessStartInfo start, string rawFile, bool input) {
   raw = rawFile; start.RedirectStandardOutput = true; start.RedirectStandardError = true;
   start.RedirectStandardInput = input; start.UseShellExecute = false; start.CreateNoWindow = true;
   start.StandardOutputEncoding = new UTF8Encoding(false); start.StandardErrorEncoding = new UTF8Encoding(false);
   process.StartInfo = start;

  }
  void Receive(string line, bool error) {
   if (line == null) { (error ? errDone : outDone).Set(); return; }
   lock(gate) {
    (error ? errors : output).AppendLine(line);
    try { if (!String.IsNullOrEmpty(raw)) File.AppendAllText(raw, line + Environment.NewLine, new UTF8Encoding(false)); } catch(Exception exception) { OutputFailure = exception.Message; }
    (error ? Console.Error : Console.Out).WriteLine(line);
    lines.Enqueue(line);
   }
  }
  // Keep original bytes separately so an external tool's legacy code page cannot lose evidence.
  sealed class RecordedStream : Stream {
   readonly Stream input; readonly FileStream recording;
   public RecordedStream(Stream source, string path) { input = source; if (!String.IsNullOrEmpty(path)) recording = new FileStream(path, FileMode.Append, FileAccess.Write, FileShare.ReadWrite); }
   public override int Read(byte[] buffer, int offset, int count) { int length=input.Read(buffer,offset,count); if(recording!=null && length>0) { recording.Write(buffer,offset,length); recording.Flush(); } return length; }
   public override bool CanRead { get { return true; } } public override bool CanSeek { get { return false; } } public override bool CanWrite { get { return false; } }
   public override long Length { get { throw new NotSupportedException(); } } public override long Position { get { throw new NotSupportedException(); } set { throw new NotSupportedException(); } }
   public override void Flush() {} public override long Seek(long offset,SeekOrigin origin) { throw new NotSupportedException(); } public override void SetLength(long value) { throw new NotSupportedException(); } public override void Write(byte[] buffer,int offset,int count) { throw new NotSupportedException(); }
   protected override void Dispose(bool disposing) { if(disposing) { if(recording!=null) recording.Dispose(); input.Dispose(); } base.Dispose(disposing); }
  }
  void Pump(Stream source, bool error) {
   try {
    string file = String.IsNullOrEmpty(raw) ? null : raw + (error ? ".stderr.bin" : ".stdout.bin");
    using(var stream=new RecordedStream(source,file)) using(var reader=new StreamReader(stream,new UTF8Encoding(false),true)) {
     string line; while((line=reader.ReadLine())!=null) Receive(line,error);
    }
   } catch(Exception exception) { OutputFailure=exception.Message; }
   finally { Receive(null,error); }
  }
  public void Start() {
   if (!process.Start()) throw new InvalidOperationException("Unable to start process");
   Thread stdout=new Thread(delegate() { Pump(process.StandardOutput.BaseStream,false); }); stdout.IsBackground=true; stdout.Start();
   Thread stderr=new Thread(delegate() { Pump(process.StandardError.BaseStream,true); }); stderr.IsBackground=true; stderr.Start();
  }
  public int Id { get { return process.Id; } }
  public bool HasExited { get { return process.HasExited; } }
  public int ExitCode { get { return process.ExitCode; } }
  // STA Windows PowerShell cannot WaitAll multiple handles; share one bounded budget instead.
  public bool Drain(int timeout) {
   Stopwatch clock=Stopwatch.StartNew();
   if (!outDone.WaitOne(timeout)) return false;
   int remaining=timeout < 0 ? Timeout.Infinite : Math.Max(0,timeout-(int)Math.Min(Int32.MaxValue,clock.ElapsedMilliseconds));
   return errDone.WaitOne(remaining);
  }
  public string StdOut { get { lock(gate) return output.ToString(); } }
  public string StdErr { get { lock(gate) return errors.ToString(); } }
  public string[] TakeLines() { List<string> result = new List<string>(); string line; while(lines.TryDequeue(out line)) result.Add(line); return result.ToArray(); }
  public void Send(string text) { process.StandardInput.WriteLine(text); process.StandardInput.Flush(); }
  public void Dispose() { process.Dispose(); }
 }
}
