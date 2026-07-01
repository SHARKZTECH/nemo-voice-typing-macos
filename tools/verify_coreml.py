import os
import sys
import argparse
import numpy as np

try:
    import onnxruntime as ort
    import coremltools as ct
except ImportError:
    print("Dependencies missing. Please install onnxruntime and coremltools:")
    print("pip install onnxruntime coremltools")
    sys.exit(1)

def verify_encoder(onnx_path, coreml_path):
    print("Verifying Encoder...")
    onnx_sess = ort.InferenceSession(onnx_path)
    coreml_model = ct.models.MLModel(coreml_path)
    
    # Generate random inputs
    audio_signal = np.random.randn(1, 65, 128).astype(np.float32)
    length = np.array([65], dtype=np.int64)
    cache_last_channel = np.random.randn(1, 24, 70, 1024).astype(np.float32)
    cache_last_time = np.random.randn(1, 24, 1024, 8).astype(np.float32)
    cache_last_channel_len = np.array([0], dtype=np.int64)
    
    onnx_inputs = {
        "audio_signal": audio_signal,
        "length": length,
        "cache_last_channel": cache_last_channel,
        "cache_last_time": cache_last_time,
        "cache_last_channel_len": cache_last_channel_len
    }
    
    # ONNX Inference
    onnx_outputs = onnx_sess.run(None, onnx_inputs)
    onnx_out_val = onnx_outputs[0]
    
    # CoreML Inference
    coreml_inputs = {
        "audio_signal": audio_signal,
        "length": length.astype(np.float32), # CoreML expects Float for Double/Int shapes sometimes
        "cache_last_channel": cache_last_channel,
        "cache_last_time": cache_last_time,
        "cache_last_channel_len": cache_last_channel_len.astype(np.float32)
    }
    coreml_outputs = coreml_model.predict(coreml_inputs)
    coreml_out_val = coreml_outputs["outputs"]
    
    # Check shape and tolerance
    print(f"ONNX output shape: {onnx_out_val.shape}")
    print(f"CoreML output shape: {coreml_out_val.shape}")
    max_diff = np.max(np.abs(onnx_out_val - coreml_out_val))
    print(f"Max absolute difference: {max_diff}")
    if max_diff < 0.1:
        print("Encoder verified successfully!")
    else:
        print("Warning: Max difference is relatively high. CoreML optimization differences may apply.")

def verify_decoder(onnx_path, coreml_path):
    print("Verifying Decoder...")
    onnx_sess = ort.InferenceSession(onnx_path)
    coreml_model = ct.models.MLModel(coreml_path)
    
    targets = np.array([[1024]], dtype=np.int64)
    h_in = np.random.randn(2, 1, 640).astype(np.float32)
    c_in = np.random.randn(2, 1, 640).astype(np.float32)
    
    onnx_inputs = {
        "targets": targets,
        "h_in": h_in,
        "c_in": c_in
    }
    
    onnx_outputs = onnx_sess.run(None, onnx_inputs)
    onnx_out_val = onnx_outputs[0]
    
    coreml_inputs = {
        "targets": targets.astype(np.float32),
        "h_in": h_in,
        "c_in": c_in
    }
    coreml_outputs = coreml_model.predict(coreml_inputs)
    coreml_out_val = coreml_outputs["decoder_output"]
    
    print(f"ONNX output shape: {onnx_out_val.shape}")
    print(f"CoreML output shape: {coreml_out_val.shape}")
    max_diff = np.max(np.abs(onnx_out_val - coreml_out_val))
    print(f"Max absolute difference: {max_diff}")
    if max_diff < 0.1:
        print("Decoder verified successfully!")
    else:
        print("Warning: Max difference is high.")

def verify_joint(onnx_path, coreml_path):
    print("Verifying Joint...")
    onnx_sess = ort.InferenceSession(onnx_path)
    coreml_model = ct.models.MLModel(coreml_path)
    
    encoder_output = np.random.randn(1, 1, 1024).astype(np.float32)
    decoder_output = np.random.randn(1, 1, 640).astype(np.float32)
    
    onnx_inputs = {
        "encoder_output": encoder_output,
        "decoder_output": decoder_output
    }
    
    onnx_outputs = onnx_sess.run(None, onnx_inputs)
    onnx_out_val = onnx_outputs[0]
    
    coreml_inputs = {
        "encoder_output": encoder_output,
        "decoder_output": decoder_output
    }
    coreml_outputs = coreml_model.predict(coreml_inputs)
    coreml_out_val = coreml_outputs["joint_output"]
    
    print(f"ONNX output shape: {onnx_out_val.shape}")
    print(f"CoreML output shape: {coreml_out_val.shape}")
    max_diff = np.max(np.abs(onnx_out_val - coreml_out_val))
    print(f"Max absolute difference: {max_diff}")
    
    # Check argmax
    onnx_argmax = np.argmax(onnx_out_val)
    coreml_argmax = np.argmax(coreml_out_val)
    print(f"ONNX argmax: {onnx_argmax}, CoreML argmax: {coreml_argmax}")
    if onnx_argmax == coreml_argmax:
        print("Joint verified successfully (argmax matches)!")
    else:
        print("Warning: argmax mismatch!")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Verify converted Nemo Voice Typing CoreML models against ONNX")
    parser.add_argument("--onnx-dir", type=str, required=True, help="Directory containing the ONNX models")
    parser.add_argument("--coreml-dir", type=str, required=True, help="Directory containing the CoreML models")
    args = parser.parse_args()
    
    verify_encoder(os.path.join(args.onnx_dir, "encoder.onnx"), os.path.join(args.coreml_dir, "Encoder.mlpackage"))
    verify_decoder(os.path.join(args.onnx_dir, "decoder.onnx"), os.path.join(args.coreml_dir, "Decoder.mlpackage"))
    verify_joint(os.path.join(args.onnx_dir, "joint.onnx"), os.path.join(args.coreml_dir, "Joint.mlpackage"))
