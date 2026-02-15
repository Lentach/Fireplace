import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { v2 as cloudinary } from 'cloudinary';

export interface UploadAvatarResult {
  secureUrl: string;
  publicId: string;
}

export interface UploadImageResult {
  secureUrl: string;
  publicId: string;
}

export interface UploadVoiceResult {
  secureUrl: string;
  publicId: string;
  duration: number;
}

@Injectable()
export class CloudinaryService {
  constructor(private configService: ConfigService) {
    cloudinary.config({
      cloud_name: this.configService.get('CLOUDINARY_CLOUD_NAME'),
      api_key: this.configService.get('CLOUDINARY_API_KEY'),
      api_secret: this.configService.get('CLOUDINARY_API_SECRET'),
    });
  }

  async uploadAvatar(
    userId: number,
    buffer: Buffer,
    mimeType: string,
  ): Promise<UploadAvatarResult> {
    const dataUri = `data:${mimeType};base64,${buffer.toString('base64')}`;

    const result = await cloudinary.uploader.upload(dataUri, {
      public_id: `avatars/user-${userId}`,
      overwrite: true,
    });

    return {
      secureUrl: result.secure_url,
      publicId: result.public_id,
    };
  }

  async uploadImage(
    userId: number,
    buffer: Buffer,
    mimeType: string,
  ): Promise<UploadImageResult> {
    const dataUri = `data:${mimeType};base64,${buffer.toString('base64')}`;

    const result = await cloudinary.uploader.upload(dataUri, {
      folder: 'message-images',
      public_id: `user-${userId}-${Date.now()}`,
    });

    return {
      secureUrl: result.secure_url,
      publicId: result.public_id,
    };
  }

  async deleteAvatar(publicId: string): Promise<void> {
    try {
      await cloudinary.uploader.destroy(publicId);
    } catch {
      // File might not exist, ignore
    }
  }

  async uploadVoiceMessage(
    userId: number,
    buffer: Buffer,
    mimeType: string,
    expiresIn?: number,
  ): Promise<UploadVoiceResult> {
    const dataUri = `data:${mimeType};base64,${buffer.toString('base64')}`;

    // Cloudinary format from mime (wav, webm, m4a)
    let format = 'm4a';
    if (mimeType.includes('wav') || mimeType.includes('wave')) {
      format = 'wav';
    } else if (mimeType.includes('webm')) {
      format = 'webm';
    } else if (mimeType.includes('mp3') || mimeType.includes('mpeg')) {
      format = 'mp3';
    }

    const uploadOptions: any = {
      folder: 'voice-messages',
      public_id: `user-${userId}-${Date.now()}`,
      resource_type: 'video', // Cloudinary uses 'video' for audio files
      format,
    };

    // Set TTL if disappearing timer is active
    if (expiresIn) {
      // Add 1 hour buffer to allow for delivery/playback
      const ttlSeconds = expiresIn + 3600;
      uploadOptions.expires_at = Math.floor(Date.now() / 1000) + ttlSeconds;
    }

    const result = await cloudinary.uploader.upload(dataUri, uploadOptions);

    return {
      secureUrl: result.secure_url,
      publicId: result.public_id,
      duration: result.duration || 0,
    };
  }
}
