import os
import sys
import argparse

try:
    import onnx
    import coremltools as ct
except ImportError:
    print("Dependencies missing. Please install coremltools and onnx:")
    print("pip install coremltools onnx")
    sys.exit(1)

def convert_encoder(onnx_path, output_path):
    print("Converting Encoder model...")
    onnx_model = onnx.load(onnx_path)
    
    # Define inputs and their shapes
    inputs = [
        ct.TensorType(name="audio_signal", shape=(1, 65, 128), dtype=ct.models.datatypes.FLOAT),
        ct.TensorType(name="length", shape=(1,), dtype=ct.models.datatypes.INT64),
        ct.TensorType(name="cache_last_channel", shape=(1, 24, 70, 1024), dtype=ct.models.datatypes.FLOAT),
        ct.TensorType(name="cache_last_time", shape=(1, 24, 1024, 8), dtype=ct.models.datatypes.FLOAT),
        ct.TensorType(name="cache_last_channel_len", shape=(1,), dtype=ct.models.datatypes.INT64)
    ]
    
    mlmodel = ct.convert(
        onnx_model,
        inputs=inputs,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16
    )
    
    mlmodel.save(output_path)
    print(f"Encoder saved to {output_path}")

def convert_decoder(onnx_path, output_path):
    print("Converting Decoder model...")
    onnx_model = onnx.load(onnx_path)
    
    inputs = [
        ct.TensorType(name="targets", shape=(1, 1), dtype=ct.models.datatypes.INT64),
        ct.TensorType(name="h_in", shape=(2, 1, 640), dtype=ct.models.datatypes.FLOAT),
        ct.TensorType(name="c_in", shape=(2, 1, 640), dtype=ct.models.datatypes.FLOAT)
    ]
    
    mlmodel = ct.convert(
        onnx_model,
        inputs=inputs,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16
    )
    
    mlmodel.save(output_path)
    print(f"Decoder saved to {output_path}")

def convert_joint(onnx_path, output_path):
    print("Converting Joint model...")
    onnx_model = onnx.load(onnx_path)
    
    inputs = [
        ct.TensorType(name="encoder_output", shape=(1, 1, 1024), dtype=ct.models.datatypes.FLOAT),
        ct.TensorType(name="decoder_output", shape=(1, 1, 640), dtype=ct.models.datatypes.FLOAT)
    ]
    
    mlmodel = ct.convert(
        onnx_model,
        inputs=inputs,
        convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16
    )
    
    mlmodel.save(output_path)
    print(f"Joint saved to {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert Nemo Voice Typing ONNX models to CoreML")
    parser.add_argument("--model-dir", type=str, required=True, help="Directory containing the ONNX models")
    parser.add_argument("--output-dir", type=str, required=True, help="Output directory for CoreML models")
    args = parser.parse_args()
    
    os.makedirs(args.output_dir, exist_ok=True)
    
    convert_encoder(os.path.join(args.model_dir, "encoder.onnx"), os.path.join(args.output_dir, "Encoder.mlpackage"))
    convert_decoder(os.path.join(args.model_dir, "decoder.onnx"), os.path.join(args.output_dir, "Decoder.mlpackage"))
    convert_joint(os.path.join(args.model_dir, "joint.onnx"), os.path.join(args.output_dir, "Joint.mlpackage"))
