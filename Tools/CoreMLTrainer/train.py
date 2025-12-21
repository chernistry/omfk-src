import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.data import Dataset, DataLoader
import pandas as pd
import numpy as np
import argparse

# Constants matching Swift implementation plan
INPUT_LENGTH = 12
ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890 -=[]\\;',./`!@#$%^&*()_+{}|:\"<>?~"
# Add Cyrillic and Hebrew
ALPHABET += "абвгдеёжзийклмнопрстуфхцчшщъыьэюяАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
ALPHABET += "אבגדהוזחטיכלמנסעפצקרשתךםןףץ"
# Mapping char -> index
CHAR_TO_IDX = {c: i+1 for i, c in enumerate(ALPHABET)} # 0 is padding
VOCAB_SIZE = len(ALPHABET) + 1

CLASSES = [
    'ru', 'en', 'he',
    'ru_from_en', 'he_from_en',
    'en_from_ru', 'en_from_he',
    'he_from_ru', 'ru_from_he'
]
CLASS_TO_IDX = {c: i for i, c in enumerate(CLASSES)}

class LayoutDataset(Dataset):
    def __init__(self, csv_file):
        self.data = pd.read_csv(csv_file)
        
    def __len__(self):
        return len(self.data)
    
    def __getitem__(self, idx):
        text = str(self.data.iloc[idx]['text'])
        label_str = self.data.iloc[idx]['label']
        
        # Tokenize / Pad
        indices = [CHAR_TO_IDX.get(c, 0) for c in text]
        if len(indices) > INPUT_LENGTH:
            indices = indices[:INPUT_LENGTH]
        else:
            indices = indices + [0] * (INPUT_LENGTH - len(indices))
            
        return torch.tensor(indices, dtype=torch.long), torch.tensor(CLASS_TO_IDX[label_str], dtype=torch.long)

class LayoutClassifier(nn.Module):
    def __init__(self):
        super(LayoutClassifier, self).__init__()
        self.embedding = nn.Embedding(VOCAB_SIZE, 32, padding_idx=0)
        self.conv1 = nn.Conv1d(32, 64, kernel_size=3, padding=1)
        self.relu = nn.ReLU()
        self.pool = nn.MaxPool1d(2)
        self.conv2 = nn.Conv1d(64, 128, kernel_size=3, padding=1)
        self.global_pool = nn.AdaptiveAvgPool1d(1)
        self.fc = nn.Linear(128, len(CLASSES))
        self.dropout = nn.Dropout(0.2)

    def forward(self, x):
        # x: [Batch, SeqLen]
        x = self.embedding(x) # [Batch, SeqLen, Emb]
        x = x.permute(0, 2, 1) # [Batch, Emb, SeqLen] for Conv1d
        x = self.conv1(x)
        x = self.relu(x)
        x = self.pool(x)
        x = self.conv2(x)
        x = self.relu(x)
        x = self.global_pool(x) # [Batch, Filters, 1]
        x = x.squeeze(2)
        x = self.dropout(x)
        x = self.fc(x)
        return x

def train(args):
    dataset = LayoutDataset(args.data)
    dataloader = DataLoader(dataset, batch_size=32, shuffle=True)
    
    model = LayoutClassifier()
    criterion = nn.CrossEntropyLoss()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    
    print("Starting training...")
    for epoch in range(args.epochs):
        total_loss = 0
        correct = 0
        total = 0
        for inputs, labels in dataloader:
            optimizer.zero_grad()
            outputs = model(inputs)
            loss = criterion(outputs, labels)
            loss.backward()
            optimizer.step()
            
            total_loss += loss.item()
            _, predicted = torch.max(outputs.data, 1)
            total += labels.size(0)
            correct += (predicted == labels).sum().item()
            
        print(f"Epoch {epoch+1}, Loss: {total_loss/len(dataloader):.4f}, Acc: {100 * correct / total:.2f}%")
        
    torch.save(model.state_dict(), args.model_out)
    print(f"Model saved to {args.model_out}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', default='training_data.csv')
    parser.add_argument('--epochs', type=int, default=5)
    parser.add_argument('--model_out', default='model.pth')
    args = parser.parse_args()
    train(args)
